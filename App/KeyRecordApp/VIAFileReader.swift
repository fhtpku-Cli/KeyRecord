import Foundation
import Dispatch
import Darwin
import os
import KeyRecordCore
import KeyRecordStore
import KeyRecordAnalysis

enum VIAFileReadError: Error { case notRegularFile, tooLarge, changed }

enum SelectedVIAReference: Sendable {
    case layout(VIALayoutReference)
    case definition(VIADefinitionReference)
}

struct SelectedVIAFile: Sendable {
    let reference: SelectedVIAReference
    let monitor: VIAFileMonitor
    let bytes: Data?
    init(reference: SelectedVIAReference, monitor: VIAFileMonitor, bytes: Data? = nil) {
        self.reference = reference; self.monitor = monitor; self.bytes = bytes
    }
}
private struct SelectedVIAReferenceBytes: Sendable { let reference: SelectedVIAReference; let bytes: Data }

struct VIAFileReadAccess: Sendable {
    let gate: KeyAvailabilityGate?
    let generation: CaptureGeneration?

    func use<T>(_ body: () throws -> T) throws -> T {
        try Task.checkCancellation()
        if let gate, let generation { return try gate.use(generation, body: body) }
        return try body()
    }
}

// The mutable event flag is locked; the source owns descriptor and scope cleanup.
final class VIAFileMonitor: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let changed = OSAllocatedUnfairLock(initialState: false)
    private let path: String
    private let original: stat
    private let notify: @Sendable () -> Void
    var hasChanged: Bool {
        let (result, shouldNotify) = changed.withLock { changed -> (Bool, Bool) in
            guard !changed else { return (true, false) }
            var current = stat()
            guard lstat(path, &current) == 0, current.st_mode & S_IFMT == S_IFREG,
                  current.st_dev == original.st_dev, current.st_ino == original.st_ino,
                  current.st_size == original.st_size,
                  current.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
                  current.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec,
                  current.st_ctimespec.tv_sec == original.st_ctimespec.tv_sec,
                  current.st_ctimespec.tv_nsec == original.st_ctimespec.tv_nsec else {
                changed = true
                return (true, true)
            }
            return (false, false)
        }
        if shouldNotify { notify() }
        return result
    }

    init(handle: FileHandle, url: URL, status: stat, scoped: Bool, notify: @escaping @Sendable () -> Void) {
        path = url.path; original = status; self.notify = notify
        let changed = self.changed
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle.fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke, .attrib], queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler {
            changed.withLock { $0 = true }
            notify()
        }
        source.setCancelHandler {
            try? handle.close()
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        source.resume()
    }

    func cancel() { changed.withLock { $0 = true }; source.cancel() }
    deinit { source.cancel() }
}

enum VIAFileReader {
    static func read(url: URL, kind: VIAImportFileKind, access: VIAFileReadAccess,
                     notify: @escaping @Sendable () -> Void) throws -> SelectedVIAFile {
        let file = try readConfiguration(url: url, access: access, notify: notify) { bytes in
            let reference: SelectedVIAReference
            switch kind {
            case .layout: reference = .layout(try VIAReferenceParser.layout(bytes))
            case .definition: reference = .definition(try VIAReferenceParser.definition(bytes))
            }
            return SelectedVIAReferenceBytes(reference: reference, bytes: bytes)
        }
        return SelectedVIAFile(reference: file.reference.reference, monitor: file.monitor, bytes: file.reference.bytes)
    }

    static func readConfiguration<T: Sendable>(url: URL, access: VIAFileReadAccess,
        notify: @escaping @Sendable () -> Void, parse: (Data) throws -> T) throws -> (reference: T, monitor: VIAFileMonitor) {
        let scoped = url.startAccessingSecurityScopedResource()
        let handle: FileHandle
        do {
            handle = try access.use {
                let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { throw VIAFileReadError.notRegularFile }
                return FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            }
        }
        catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            try? handle.close()
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw VIAFileReadError.notRegularFile
        }
        let monitor = VIAFileMonitor(handle: handle, url: url, status: info, scoped: scoped, notify: notify)
        do {
            var bytes = Data()
            let maximum = VIAReferenceParser.maximumInputBytes
            while bytes.count <= maximum {
                if monitor.hasChanged { throw VIAFileReadError.changed }
                let chunk = try access.use { try handle.read(upToCount: min(64 * 1_024, maximum + 1 - bytes.count)) }
                guard let chunk, !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
            guard bytes.count <= maximum else { throw VIAFileReadError.tooLarge }
            try access.use {}
            let reference = try parse(bytes)
            try access.use {}
            guard !monitor.hasChanged else { throw VIAFileReadError.changed }
            return (reference: reference, monitor: monitor)
        } catch {
            monitor.cancel()
            throw error
        }
    }
}
