import Darwin
import Foundation

enum RunAllPublicationBoundary: CaseIterable {
    case beforeReplace
    case afterReplace
    case afterDirectorySync
}

enum RunAllPublicationError: Error {
    case injectedCrash(RunAllPublicationBoundary)
    case posix(String, Int32)
}

enum RunAllPublication {
    static func replace(
        staged: URL,
        output: URL,
        crashAt: RunAllPublicationBoundary? = nil
    ) throws {
        try crash(.beforeReplace, requested: crashAt)
        if FileManager.default.fileExists(atPath: output.path) {
            guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, output.path, UInt32(RENAME_SWAP)) == 0 else {
                throw RunAllPublicationError.posix("renameatx_np", errno)
            }
        } else {
            guard Darwin.rename(staged.path, output.path) == 0 else {
                throw RunAllPublicationError.posix("rename", errno)
            }
        }
        try crash(.afterReplace, requested: crashAt)
        let descriptor = Darwin.open(output.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw RunAllPublicationError.posix("open", errno) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw RunAllPublicationError.posix("fsync", errno) }
        try crash(.afterDirectorySync, requested: crashAt)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
    }

    private static func crash(
        _ boundary: RunAllPublicationBoundary,
        requested: RunAllPublicationBoundary?
    ) throws {
        if requested == boundary { throw RunAllPublicationError.injectedCrash(boundary) }
    }
}
