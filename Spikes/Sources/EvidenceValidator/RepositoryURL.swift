import Foundation
import Darwin

// Canonicalizes cwd-relative CLI paths before they cross the trust boundary.
// URL standardization alone leaves "." under the PWD spelling (/var/...) while
// relative subpaths resolve through the kernel (/private/var/...), which makes
// repository-relative path checks fail; realpath on the deepest existing
// ancestor collapses symlinked prefixes identically for every argument shape.
enum RepositoryURL {
    static func resolve(_ path: String, currentDirectory: String = FileManager.default.currentDirectoryPath) -> URL {
        let expanded: String
        if path == "." {
            expanded = currentDirectory
        } else {
            expanded = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentDirectory)).standardizedFileURL.path
        }
        return URL(fileURLWithPath: canonicalPath(expanded))
    }

    // Canonicalizes the deepest existing ancestor directory with realpath and
    // re-appends the remaining tail, so not-yet-created outputs and symlinked
    // leaves get the same physical prefix (/private/var) as their repository
    // base while the leaf itself stays unexpanded: downstream checks must still
    // observe and reject a symlinked input rather than its target.
    static func canonicalPath(_ path: String) -> String {
        let manager = FileManager.default
        var suffix: [String] = [(path as NSString).lastPathComponent]
        var ancestor = (path as NSString).deletingLastPathComponent
        while !manager.fileExists(atPath: ancestor) {
            suffix.insert((ancestor as NSString).lastPathComponent, at: 0)
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        let real = realpathExisting(ancestor) ?? ancestor
        return suffix.reduce(real) { ($0 as NSString).appendingPathComponent($1) }
    }

    private static func realpathExisting(_ path: String) -> String? {
        path.withCString { pointer in
            guard let resolved = Darwin.realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
