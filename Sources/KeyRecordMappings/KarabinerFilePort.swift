import Darwin
import Foundation
import KeyRecordConfigurationRead
import KeyRecordCore
import KeyRecordStore

public final class KarabinerFilePort: KarabinerConfigurationPort, @unchecked Sendable {
    private let target: URL
    private let directory: URL
    private let directoryDescriptor: Int32
    private let directoryDevice: dev_t
    private let directoryInode: ino_t
    private let runtime: @Sendable () throws -> KarabinerRuntimeContext
    private let gate: KeyAvailabilityGate
    private let generation: CaptureGeneration
    private let injection: DurabilityInjection
    private let lock = NSLock()
    public init(target: URL, gate: KeyAvailabilityGate,
                runtime: @escaping @Sendable () throws -> KarabinerRuntimeContext,
                injection: DurabilityInjection = .none) throws {
        let directory = target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        self.directory = directory; self.target = directory.appendingPathComponent(target.lastPathComponent)
        self.gate = gate; self.generation = try gate.begin()
        self.runtime = runtime; self.injection = injection
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw KarabinerMappingError.unavailable }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else {
            Darwin.close(descriptor); throw KarabinerMappingError.unavailable
        }
        directoryDescriptor = descriptor; directoryDevice = status.st_dev; directoryInode = status.st_ino
    }
    deinit { Darwin.close(directoryDescriptor) }
    public func context() throws -> KarabinerRuntimeContext {
        try gate.use(generation) { try validateDirectory(); return try runtime() }
    }
    public func read() throws -> Data { try gate.use(generation) { try lock.withLock { try readFile() } } }
    public func replace(expected: Data, with bytes: Data, context: KarabinerRuntimeContext) throws {
        try gate.use(generation) {
            try lock.withLock {
                guard context.authority != .readOnly else { throw KarabinerMappingError.readOnlyVersion }
                if context.authority == .temporaryConfiguration {
                    let path = target.resolvingSymlinksInPath().standardizedFileURL.path
                    let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                    guard path.hasPrefix(temporaryRoot + "/") || path.hasPrefix("/private/tmp/") else { throw KarabinerMappingError.readOnlyVersion }
                } else if case .qualifiedAdapter(_, let profiles) = context.authority {
                    guard let profile = profiles.sorted().first else { throw KarabinerMappingError.readOnlyVersion }
                    try context.requireWrite(profile: profile)
                }
                guard try runtime() == context else { throw KarabinerMappingError.externalChange }
                guard try readFile() == expected else { throw KarabinerMappingError.externalChange }
                _ = try JSONDocumentRanges(bytes)
                try AtomicFileSystem().commitFile(name: target.lastPathComponent, inDirectory: directoryDescriptor,
                    bytes: bytes, phase: .data, injection: injection) {
                        guard try self.runtime() == context, try self.readFile() == expected else { throw KarabinerMappingError.externalChange }
                    }
            }
        }
    }
    private func validateDirectory() throws {
        var status = stat()
        guard lstat(directory.path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR,
              status.st_dev == directoryDevice, status.st_ino == directoryInode else { throw KarabinerMappingError.externalChange }
    }
    private func readFile() throws -> Data {
        try validateDirectory()
        let descriptor = openat(directoryDescriptor, target.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw KarabinerMappingError.unavailable }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= ConfigurationReadLimits.maximumInputBytes else { throw KarabinerMappingError.invalidConfiguration }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw KarabinerMappingError.unavailable }
            if count == 0 { break }
            guard result.count + count <= ConfigurationReadLimits.maximumInputBytes else { throw KarabinerMappingError.invalidConfiguration }
            result.append(contentsOf: buffer.prefix(count))
        }
        var after = stat(), pathStatus = stat()
        guard fstat(descriptor, &after) == 0, fstatat(directoryDescriptor, target.lastPathComponent, &pathStatus, AT_SYMLINK_NOFOLLOW) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              pathStatus.st_dev == after.st_dev, pathStatus.st_ino == after.st_ino else { throw KarabinerMappingError.externalChange }
        try validateDirectory()
        _ = try JSONDocumentRanges(result)
        return result
    }
}
