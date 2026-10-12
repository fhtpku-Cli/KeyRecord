import Darwin
import Foundation
import KeyRecordConfigurationRead
import KeyRecordCore
import KeyRecordStore

public final class KarabinerFilePort: KarabinerConfigurationPort, @unchecked Sendable {
    private let target: URL
    private let runtime: @Sendable () throws -> KarabinerRuntimeContext
    private let gate: KeyAvailabilityGate
    private let generation: CaptureGeneration
    private let injection: DurabilityInjection
    private let lock = NSLock()
    public init(target: URL, gate: KeyAvailabilityGate,
                runtime: @escaping @Sendable () throws -> KarabinerRuntimeContext,
                injection: DurabilityInjection = .none) throws {
        self.target = target; self.gate = gate; self.generation = try gate.begin()
        self.runtime = runtime; self.injection = injection
    }
    public func context() throws -> KarabinerRuntimeContext { try gate.use(generation) { try runtime() } }
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
                try AtomicFileSystem().commitFile(name: target.lastPathComponent, in: target.deletingLastPathComponent(),
                    bytes: bytes, phase: .data, injection: injection) {
                        guard try self.runtime() == context, try self.readFile() == expected else { throw KarabinerMappingError.externalChange }
                    }
            }
        }
    }
    private func readFile() throws -> Data {
        let descriptor = Darwin.open(target.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
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
        guard fstat(descriptor, &after) == 0, lstat(target.path, &pathStatus) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              pathStatus.st_dev == after.st_dev, pathStatus.st_ino == after.st_ino else { throw KarabinerMappingError.externalChange }
        _ = try JSONDocumentRanges(result)
        return result
    }
}
