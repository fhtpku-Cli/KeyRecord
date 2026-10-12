import Darwin
import Foundation
import KeyRecordCore
import KeyRecordStore
import KeyRecordConfigurationRead

public final class FirmwareFileDestination: FirmwareExportDestination, @unchecked Sendable {
    public let reference: FirmwareExportReference
    private let target: URL
    private let gate: KeyAvailabilityGate
    private let generation: CaptureGeneration
    private let lock = NSLock()
    private let injection: DurabilityInjection
    private let scoped: Bool
    public init(target: URL, gate: KeyAvailabilityGate, injection: DurabilityInjection = .none) throws {
        self.target = target; self.gate = gate; generation = try gate.begin(); self.injection = injection
        scoped = target.startAccessingSecurityScopedResource()
        do {
            reference = FirmwareExportReference(bookmark: try target.deletingLastPathComponent().bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil), location: Self.location(target))
        } catch {
            if scoped { target.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    public convenience init(reference: FirmwareExportReference, gate: KeyAvailabilityGate) throws {
        var stale = false
        let directory = try URL(resolvingBookmarkData: reference.bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        let target = directory.appendingPathComponent(URL(fileURLWithPath: reference.location).lastPathComponent)
        guard Self.location(target) == reference.location else { throw FirmwareError.externalChange }
        try self.init(target: target, gate: gate)
    }
    private static func location(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }
    public func read() throws -> Data? { try gate.use(generation) { try lock.withLock { try readFile() } } }
    public func write(_ bytes: Data) throws {
        try gate.use(generation) {
            try lock.withLock {
                _ = try JSONDocumentRanges(bytes)
                let previous = try readFile()
                try AtomicFileSystem().commitFile(name: target.lastPathComponent, in: target.deletingLastPathComponent(),
                    bytes: bytes, phase: .data, injection: injection) {
                        guard try self.readFile() == previous else { throw FirmwareError.externalChange }
                    }
            }
        }
    }
    private func readFile() throws -> Data? {
        let descriptor = Darwin.open(target.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw FirmwareError.unavailable }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_nlink == 1, before.st_size >= 0,
              before.st_size <= ConfigurationReadLimits.maximumInputBytes else { throw FirmwareError.invalidDocument }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw FirmwareError.unavailable }
            if count == 0 { break }
            guard bytes.count + count <= ConfigurationReadLimits.maximumInputBytes else { throw FirmwareError.invalidDocument }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat(), path = stat()
        guard fstat(descriptor, &after) == 0, lstat(target.path, &path) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              path.st_dev == after.st_dev, path.st_ino == after.st_ino else { throw FirmwareError.externalChange }
        _ = try JSONDocumentRanges(bytes)
        return bytes
    }
    deinit { if scoped { target.stopAccessingSecurityScopedResource() } }
}
