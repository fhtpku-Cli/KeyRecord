import Foundation

public enum FileSystemError: Error, Equatable, Sendable {
    case rootSymlink, rootNotDirectory
    case insecureRootPermissions(mode: UInt16), foreignOwner
    case symlinkEncountered(name: String), notRegularFile(name: String), fileTooLarge
    case posix(operation: String, code: Int32)
}

/// Which durable phase an injected boundary belongs to. Data files always commit before
/// the manifest is allowed to reference them.
public enum DurabilityPhase: String, CaseIterable, Sendable { case data, manifest, cleanup }

/// Points around write/fsync/rename/dir-fsync. Process fault injection (`killAt`) sends a
/// real SIGKILL to the running process; `failAt` throws for in-process negative tests.
public enum DurabilityBoundary: String, CaseIterable, Sendable {
    case afterWrite, afterFileFsync, afterRename, afterDirectoryFsync
}

public struct DurabilityInjection: Sendable {
    public let killPhase: DurabilityPhase?
    public let killAt: DurabilityBoundary?
    public let failPhase: DurabilityPhase?
    public let failAt: DurabilityBoundary?

    public init(killPhase: DurabilityPhase? = nil, killAt: DurabilityBoundary? = nil,
                failPhase: DurabilityPhase? = nil, failAt: DurabilityBoundary? = nil) {
        self.killPhase = killPhase; self.killAt = killAt
        self.failPhase = failPhase; self.failAt = failAt
    }
    public static let none = DurabilityInjection()
}

public enum RootEntryKind: Sendable { case regular, symlink, other }
public struct RootEntry: Sendable { public let name: String; public let kind: RootEntryKind }

/// POSIX filesystem with a private 0700 root, 0600 regular files, O_NOFOLLOW opens and
/// explicit data-then-manifest durability ordering. Every boundary is observable to the
/// real-process crash probe and to in-process failure tests.
public struct AtomicFileSystem: Sendable {
    public static let tempPrefix = ".keyrecord-tmp-"
    static let privateRootMode: mode_t = 0o700
    static let privateFileMode: mode_t = 0o600
    static let maximumReadBytes = AuthenticatedStorageEnvelope.headerByteCount
        + AuthenticatedStorageEnvelope.maximumCiphertextBytes + 16

    public init() {}

    public func preparePrivateRoot(at root: URL) throws {
        if mkdir(root.path, Self.privateRootMode) != 0, errno != EEXIST {
            throw FileSystemError.posix(operation: "mkdir(root)", code: errno)
        }
        let status = try lstatRoot(root)
        switch status.st_mode & S_IFMT {
        case S_IFLNK: throw FileSystemError.rootSymlink
        case S_IFDIR: break
        default: throw FileSystemError.rootNotDirectory
        }
        guard status.st_uid == getuid() else { throw FileSystemError.foreignOwner }
        guard (status.st_mode & 0o777) == Self.privateRootMode else {
            throw FileSystemError.insecureRootPermissions(mode: UInt16(status.st_mode & 0o777))
        }
    }

    public func rootExists(_ root: URL) -> Bool {
        guard let status = lstatPath(root.path) else { return false }
        return (status.st_mode & S_IFMT) == S_IFDIR
    }

    public func listEntries(in root: URL) throws -> [RootEntry] {
        guard let directory = opendir(root.path) else {
            throw FileSystemError.posix(operation: "opendir", code: errno)
        }
        defer { closedir(directory) }
        var entries: [RootEntry] = []
        while let pointer = readdir(directory) {
            var record = pointer.pointee
            let name = withUnsafePointer(to: &record.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            guard let status = lstatPath(root.appendingPathComponent(name).path) else {
                throw FileSystemError.posix(operation: "lstat(entry)", code: errno)
            }
            let kind: RootEntryKind
            switch status.st_mode & S_IFMT {
            case S_IFREG: kind = .regular
            case S_IFLNK: kind = .symlink
            default: kind = .other
            }
            entries.append(RootEntry(name: name, kind: kind))
        }
        return entries.sorted { $0.name < $1.name }
    }

    public func readWholeFile(name: String, in root: URL) throws -> Data {
        let path = root.appendingPathComponent(name).path
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw FileSystemError.posix(operation: "open(no-follow)", code: errno) }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw FileSystemError.posix(operation: "fstat", code: errno) }
        guard (status.st_mode & S_IFMT) == S_IFREG else { throw FileSystemError.notRegularFile(name: name) }
        guard status.st_size <= Self.maximumReadBytes else { throw FileSystemError.fileTooLarge }
        var data = Data()
        data.reserveCapacity(Int(status.st_size))
        var remaining = Int(status.st_size)
        while remaining > 0 {
            let count = min(65_536, remaining)
            var buffer = Data(count: count)
            let written = try buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { throw FileSystemError.posix(operation: "read", code: EIO) }
                return read(fd, base, count)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw FileSystemError.posix(operation: "read", code: errno)
            }
            guard written > 0 else { throw FileSystemError.posix(operation: "read-zero", code: EIO) }
            data.append(buffer.prefix(written))
            remaining -= written
        }
        return data
    }

    public func commitFile(name: String, in root: URL, bytes: Data, phase: DurabilityPhase,
                           injection: DurabilityInjection = .none) throws {
        var state = ReplacementState()
        do {
            try createWriteAndSync(name: name, in: root, bytes: bytes,
                                   phase: phase, injection: injection, state: &state)
        } catch {
            try? cleanup(state: &state)
            throw error
        }
    }

    public func removeFile(name: String, in root: URL, injection: DurabilityInjection = .none) throws {
        let path = root.appendingPathComponent(name).path
        guard unlink(path) == 0 || errno == ENOENT else {
            throw FileSystemError.posix(operation: "unlink", code: errno)
        }
        try hit(.afterRename, phase: .cleanup, injection: injection)
        try syncDirectory(root)
        try hit(.afterDirectoryFsync, phase: .cleanup, injection: injection)
    }

    private func createWriteAndSync(name: String, in root: URL, bytes: Data, phase: DurabilityPhase,
                                    injection: DurabilityInjection, state: inout ReplacementState) throws {
        let (fd, tempPath) = try createTemporaryFile(in: root)
        state.fd = fd; state.tempPath = tempPath
        try fchmodDescriptor(fd)
        try writeAll(bytes, fd: fd)
        try hit(.afterWrite, phase: phase, injection: injection)
        try sync(fd, operation: "fsync(file)")
        try hit(.afterFileFsync, phase: phase, injection: injection)
        guard close(fd) == 0 else {
            state.fd = nil
            throw FileSystemError.posix(operation: "close(file)", code: errno)
        }
        state.fd = nil
        guard rename(tempPath, root.appendingPathComponent(name).path) == 0 else {
            throw FileSystemError.posix(operation: "rename", code: errno)
        }
        state.renamed = true
        try hit(.afterRename, phase: phase, injection: injection)
        try syncDirectory(root)
        try hit(.afterDirectoryFsync, phase: phase, injection: injection)
    }

    private func createTemporaryFile(in root: URL) throws -> (Int32, String) {
        var template = Array(root.appendingPathComponent(Self.tempPrefix + "XXXXXXXXXX").path.utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress) }
        guard fd >= 0 else { throw FileSystemError.posix(operation: "mkstemp", code: errno) }
        let path = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return (fd, path)
    }

    private func fchmodDescriptor(_ fd: Int32) throws {
        guard fchmod(fd, Self.privateFileMode) == 0 else {
            throw FileSystemError.posix(operation: "fchmod", code: errno)
        }
    }

    private func writeAll(_ bytes: Data, fd: Int32) throws {
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw FileSystemError.posix(operation: "write", code: errno)
                }
                guard written > 0 else { throw FileSystemError.posix(operation: "write-zero", code: EIO) }
                offset += written
            }
        }
    }

    private func hit(_ boundary: DurabilityBoundary, phase: DurabilityPhase,
                     injection: DurabilityInjection) throws {
        if injection.failPhase == phase, injection.failAt == boundary {
            throw FileSystemError.posix(operation: "injected-\(phase.rawValue)-\(boundary.rawValue)", code: ECANCELED)
        }
        guard injection.killPhase == phase, injection.killAt == boundary else { return }
        kill(getpid(), SIGKILL)
        Thread.sleep(forTimeInterval: 30)
    }

    private func sync(_ fd: Int32, operation: String) throws {
        while fsync(fd) != 0 {
            if errno == EINTR { continue }
            throw FileSystemError.posix(operation: operation, code: errno)
        }
    }

    private func syncDirectory(_ root: URL) throws {
        let fd = open(root.path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw FileSystemError.posix(operation: "open(dir)", code: errno) }
        defer { close(fd) }
        try sync(fd, operation: "fsync(dir)")
    }

    private func cleanup(state: inout ReplacementState) throws {
        if let fd = state.fd { close(fd); state.fd = nil }
        guard !state.renamed, let tempPath = state.tempPath else { return }
        if unlink(tempPath) != 0, errno != ENOENT {
            throw FileSystemError.posix(operation: "unlink(temp)", code: errno)
        }
    }

    private func lstatRoot(_ root: URL) throws -> stat {
        guard let status = lstatPath(root.path) else {
            throw FileSystemError.posix(operation: "lstat(root)", code: errno)
        }
        return status
    }
}

private func lstatPath(_ path: String) -> stat? {
    var status = stat()
    return lstat(path, &status) == 0 ? status : nil
}

private struct ReplacementState { var fd: Int32?; var tempPath: String?; var renamed = false }
