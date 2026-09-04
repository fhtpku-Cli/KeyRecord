import Darwin
import Foundation

public enum AtomicReplacementFailureStep: String, CaseIterable, Codable, Hashable, Sendable {
    case writeTemp
    case fileFsync
    case rename
    case directoryFsync
}

public enum AtomicReplacementCrashBoundary: String, CaseIterable, Codable, Hashable, Sendable {
    case beforeWriteTemp
    case afterWriteTemp
    case beforeFileFsync
    case afterFileFsync
    case beforeRename
    case afterRename
    case beforeDirectoryFsync
    case afterDirectoryFsync

    public var isAfterRename: Bool {
        switch self {
        case .afterRename, .beforeDirectoryFsync, .afterDirectoryFsync: true
        default: false
        }
    }
}

public struct AtomicReplacementInjection: Sendable {
    public let failureAt: AtomicReplacementFailureStep?
    public let crashAt: AtomicReplacementCrashBoundary?
    public let writeFailureAfterBytes: Int?
    public let maximumWriteSize: Int

    public init(
        failureAt: AtomicReplacementFailureStep? = nil,
        crashAt: AtomicReplacementCrashBoundary? = nil,
        writeFailureAfterBytes: Int? = nil,
        maximumWriteSize: Int = Int.max
    ) {
        self.failureAt = failureAt
        self.crashAt = crashAt
        self.writeFailureAfterBytes = writeFailureAfterBytes
        self.maximumWriteSize = max(1, maximumWriteSize)
    }
}

public enum AtomicReplacementError: Error, Equatable, CustomStringConvertible, Sendable {
    case injectedFailure(AtomicReplacementFailureStep)
    case injectedCrash(AtomicReplacementCrashBoundary)
    case invalidTarget
    case posix(operation: String, code: Int32)
    case cleanupFailed(primary: String, cleanup: String)

    public var description: String {
        switch self {
        case let .injectedFailure(step): "injected failure at \(step.rawValue)"
        case let .injectedCrash(boundary): "injected crash at \(boundary.rawValue)"
        case .invalidTarget: "target must have a nonempty filename"
        case let .posix(operation, code): "\(operation) failed with errno \(code)"
        case let .cleanupFailed(primary, cleanup): "\(primary); cleanup failed: \(cleanup)"
        }
    }
}

public struct AtomicReplacementReport: Equatable, Sendable {
    public let temporaryDirectory: URL
    public let writeCallCount: Int
}

public struct POSIXAtomicReplacement: Sendable {
    public static let temporaryPrefix = ".keyrecord-atomic-"

    public init() {}

    public func replace(
        target: URL,
        bytes: Data,
        injection: AtomicReplacementInjection = AtomicReplacementInjection()
    ) throws -> AtomicReplacementReport {
        guard !target.lastPathComponent.isEmpty else { throw AtomicReplacementError.invalidTarget }
        let directory = target.deletingLastPathComponent()
        var state = ReplacementState()
        do {
            try crashIfRequested(.beforeWriteTemp, injection: injection, state: &state)
            let opened = try createTemporaryFile(in: directory)
            state.fileDescriptor = opened.descriptor
            state.temporaryPath = opened.path
            try writeAll(bytes, descriptor: opened.descriptor, injection: injection, writeCalls: &state.writeCalls)
            try crashIfRequested(.afterWriteTemp, injection: injection, state: &state)
            try crashIfRequested(.beforeFileFsync, injection: injection, state: &state)
            try failIfRequested(.fileFsync, injection: injection)
            try sync(opened.descriptor, operation: "fsync(temp)")
            try crashIfRequested(.afterFileFsync, injection: injection, state: &state)
            try close(&state.fileDescriptor, operation: "close(temp)")
            try crashIfRequested(.beforeRename, injection: injection, state: &state)
            try failIfRequested(.rename, injection: injection)
            try rename(opened.path, target.path)
            state.wasRenamed = true
            try crashIfRequested(.afterRename, injection: injection, state: &state)
            let directoryDescriptor = try openDirectory(directory.path)
            state.directoryDescriptor = directoryDescriptor
            try crashIfRequested(.beforeDirectoryFsync, injection: injection, state: &state)
            try failIfRequested(.directoryFsync, injection: injection)
            try sync(directoryDescriptor, operation: "fsync(directory)")
            try crashIfRequested(.afterDirectoryFsync, injection: injection, state: &state)
            try close(&state.directoryDescriptor, operation: "close(directory)")
            return AtomicReplacementReport(temporaryDirectory: directory, writeCallCount: state.writeCalls)
        } catch let primary {
            do {
                try cleanup(state: &state)
            } catch let cleanupError {
                throw AtomicReplacementError.cleanupFailed(primary: String(describing: primary), cleanup: String(describing: cleanupError))
            }
            throw primary
        }
    }

    public static func cleanupStaleTemporaryFiles(in directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for name in names where name.hasPrefix(temporaryPrefix) {
            let path = directory.appendingPathComponent(name).path
            guard Darwin.unlink(path) == 0 else {
                throw AtomicReplacementError.posix(operation: "unlink(stale-temp)", code: errno)
            }
        }
    }

    private func createTemporaryFile(in directory: URL) throws -> (descriptor: Int32, path: String) {
        var template = Array(directory.appendingPathComponent(Self.temporaryPrefix + "XXXXXX").path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            Darwin.mkstemp(buffer.baseAddress)
        }
        guard descriptor >= 0 else { throw AtomicReplacementError.posix(operation: "mkstemp", code: errno) }
        return (descriptor, String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }

    private func writeAll(
        _ data: Data,
        descriptor: Int32,
        injection: AtomicReplacementInjection,
        writeCalls: inout Int
    ) throws {
        try failIfRequested(.writeTemp, injection: injection, bytesWritten: 0)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                try failIfRequested(.writeTemp, injection: injection, bytesWritten: offset)
                let untilInjectedFailure = injection.writeFailureAfterBytes.map { max(1, $0 - offset) } ?? Int.max
                let count = min(rawBuffer.count - offset, injection.maximumWriteSize, untilInjectedFailure)
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), count)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw AtomicReplacementError.posix(operation: "write(temp)", code: errno)
                }
                guard written > 0 else { throw AtomicReplacementError.posix(operation: "write(temp-zero)", code: EIO) }
                offset += written
                writeCalls += 1
            }
        }
    }

    private func failIfRequested(
        _ step: AtomicReplacementFailureStep,
        injection: AtomicReplacementInjection,
        bytesWritten: Int? = nil
    ) throws {
        guard injection.failureAt == step else { return }
        if step == .writeTemp, let threshold = injection.writeFailureAfterBytes, (bytesWritten ?? 0) < threshold { return }
        throw AtomicReplacementError.injectedFailure(step)
    }

    private func crashIfRequested(
        _ boundary: AtomicReplacementCrashBoundary,
        injection: AtomicReplacementInjection,
        state: inout ReplacementState
    ) throws {
        guard injection.crashAt == boundary else { return }
        state.preserveTemporaryFile = true
        throw AtomicReplacementError.injectedCrash(boundary)
    }

    private func sync(_ descriptor: Int32, operation: String) throws {
        while Darwin.fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw AtomicReplacementError.posix(operation: operation, code: errno)
        }
    }

    private func rename(_ source: String, _ destination: String) throws {
        guard Darwin.rename(source, destination) == 0 else {
            throw AtomicReplacementError.posix(operation: "rename", code: errno)
        }
    }

    private func openDirectory(_ path: String) throws -> Int32 {
        let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw AtomicReplacementError.posix(operation: "open(directory)", code: errno) }
        return descriptor
    }

    private func close(_ descriptor: inout Int32?, operation: String) throws {
        guard let value = descriptor else { return }
        descriptor = nil
        guard Darwin.close(value) == 0 else { throw AtomicReplacementError.posix(operation: operation, code: errno) }
    }

    private func cleanup(state: inout ReplacementState) throws {
        try close(&state.fileDescriptor, operation: "close(temp-cleanup)")
        try close(&state.directoryDescriptor, operation: "close(directory-cleanup)")
        guard !state.preserveTemporaryFile, !state.wasRenamed, let path = state.temporaryPath else { return }
        guard Darwin.unlink(path) == 0 || errno == ENOENT else {
            throw AtomicReplacementError.posix(operation: "unlink(temp-cleanup)", code: errno)
        }
    }
}

private struct ReplacementState {
    var fileDescriptor: Int32?
    var directoryDescriptor: Int32?
    var temporaryPath: String?
    var writeCalls = 0
    var wasRenamed = false
    var preserveTemporaryFile = false
}
