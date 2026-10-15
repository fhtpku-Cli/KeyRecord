import Foundation

extension AtomicFileSystem {
    // Borrow a caller-owned directory descriptor for this synchronous commit.
    // Rename, cleanup and fsync must stay in that directory even if its path moves.
    public func commitFile(name: String, inDirectory descriptor: Int32, bytes: Data, phase: DurabilityPhase,
                           injection: DurabilityInjection = .none, beforeRename: () throws -> Void = {}) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileSystemError.posix(operation: "invalid file name", code: EINVAL)
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { throw FileSystemError.rootNotDirectory }
        let temporary = Self.tempPrefix + UUID().uuidString
        let fd = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, Self.privateFileMode)
        guard fd >= 0 else { throw FileSystemError.posix(operation: "openat(temporary)", code: errno) }
        var openDescriptor: Int32? = fd
        var renamed = false
        defer {
            if let openDescriptor { close(openDescriptor) }
            if !renamed { unlinkat(descriptor, temporary, 0) }
        }
        try fchmodDescriptor(fd)
        try writeAll(bytes, fd: fd)
        try hit(.afterWrite, phase: phase, injection: injection)
        try sync(fd, operation: "fsync(file)")
        try hit(.afterFileFsync, phase: phase, injection: injection)
        let closed = close(fd)
        openDescriptor = nil
        guard closed == 0 else { throw FileSystemError.posix(operation: "close(file)", code: errno) }
        try beforeRename()
        guard renameat(descriptor, temporary, descriptor, name) == 0 else {
            throw FileSystemError.posix(operation: "renameat", code: errno)
        }
        renamed = true
        try hit(.afterRename, phase: phase, injection: injection)
        try sync(descriptor, operation: "fsync(directory)")
        try hit(.afterDirectoryFsync, phase: phase, injection: injection)
    }

    func fchmodDescriptor(_ fd: Int32) throws {
        guard fchmod(fd, Self.privateFileMode) == 0 else {
            throw FileSystemError.posix(operation: "fchmod", code: errno)
        }
    }

    func writeAll(_ bytes: Data, fd: Int32) throws {
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

    func hit(_ boundary: DurabilityBoundary, phase: DurabilityPhase,
             injection: DurabilityInjection) throws {
        if injection.failPhase == phase, injection.failAt == boundary {
            throw FileSystemError.posix(operation: "injected-\(phase.rawValue)-\(boundary.rawValue)", code: ECANCELED)
        }
        guard injection.killPhase == phase, injection.killAt == boundary else { return }
        kill(getpid(), SIGKILL)
        Thread.sleep(forTimeInterval: 30)
    }

    func sync(_ fd: Int32, operation: String) throws {
        while fsync(fd) != 0 {
            if errno == EINTR { continue }
            throw FileSystemError.posix(operation: operation, code: errno)
        }
    }
}
