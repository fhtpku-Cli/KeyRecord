import Foundation
import Darwin

public enum PasswordBackupFile {
    public static func read(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw PasswordBackupError.invalidArchive }
        defer { Darwin.close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= PasswordBackup.maximumArchiveBytes
        else { throw PasswordBackupError.limitExceeded }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw PasswordBackupError.invalidArchive }
            if count == 0 { break }
            guard data.count + count <= PasswordBackup.maximumArchiveBytes else { throw PasswordBackupError.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    public static func writeNew(_ archive: Data, to url: URL) throws {
        guard archive.count <= PasswordBackup.maximumArchiveBytes else { throw PasswordBackupError.limitExceeded }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".keyrecord-backup-\(UUID().uuidString)")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw PasswordBackupError.invalidArchive }
        defer { Darwin.close(fd); unlink(temp.path) }
        try archive.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw PasswordBackupError.invalidArchive }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw PasswordBackupError.invalidArchive }
        // link publishes a complete ciphertext only if the chosen path is still absent.
        guard link(temp.path, url.path) == 0 else { throw PasswordBackupError.destinationNotEmpty }
        let parent = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw PasswordBackupError.invalidArchive }
        defer { Darwin.close(parent) }
        guard fsync(parent) == 0 else { throw PasswordBackupError.invalidArchive }
    }
}
