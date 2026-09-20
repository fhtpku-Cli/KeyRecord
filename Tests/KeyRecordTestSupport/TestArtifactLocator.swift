import Foundation

/// Locates SwiftPM build products and per-run scratch space without assuming any
/// particular scratch-path directory name.
///
/// The previous implementation walked ancestors until it found a directory literally
/// named `build`, which only matched the bespoke `--scratch-path <attempt>/build/root`
/// layout used by the QA runner and failed under the default `.build` layout. A
/// resolver failure is a harness fault, not a product-logic failure, so every error
/// case here is explicit and named.
public enum TestArtifactLocator {
    public enum LocatorError: Error, CustomStringConvertible, Equatable {
        case productsDirectoryNotFound(from: String)
        case scratchRootNotFound(from: String)
        case pathEscapesScratchRoot(path: String, root: String)
        case probeMissing(String)
        case probeNotExecutable(String)

        public var description: String {
            switch self {
            case .productsDirectoryNotFound(let from):
                return "harness: build products directory not found from \(from)"
            case .scratchRootNotFound(let from):
                return "harness: scratch root not found from \(from)"
            case .pathEscapesScratchRoot(let path, let root):
                return "harness: \(path) escapes scratch root \(root)"
            case .probeMissing(let path):
                return "harness: probe missing at \(path)"
            case .probeNotExecutable(let path):
                return "harness: probe not executable at \(path)"
            }
        }
    }

    private final class BundleAnchor: NSObject {}

    /// Canonical location of the currently running test bundle, symlinks resolved.
    /// SwiftPM's `.build/debug` is a symlink into `.build/out/Products/Debug`; resolving
    /// first makes the ancestor search stable across both layouts.
    public static var bundleURL: URL {
        canonical(Bundle(for: BundleAnchor.self).bundleURL)
    }

    public static func canonical(_ url: URL) -> URL {
        URL(fileURLWithPath: (url.path as NSString).resolvingSymlinksInPath).standardizedFileURL
    }

    /// The directory holding built products (`*.xctest`, `*.swiftmodule`, `Modules/`).
    /// Under SwiftPM this is the parent of the running `.xctest` bundle; the ancestor
    /// walk is a fallback for hosts that nest the bundle more deeply.
    public static func productsDirectory() throws -> URL {
        var location = bundleURL
        for _ in 0..<12 {
            if location.pathExtension == "xctest" {
                location.deleteLastPathComponent()
                continue
            }
            if containsBuildProducts(location) { return location }
            let parent = location.deletingLastPathComponent()
            if parent.path == location.path { break }
            location = parent
        }
        throw LocatorError.productsDirectoryNotFound(from: bundleURL.path)
    }

    private static func containsBuildProducts(_ directory: URL) -> Bool {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory.path) else { return false }
        let hasModules = entries.contains("Modules")
            || entries.contains { $0.hasSuffix(".swiftmodule") }
        let hasBinary = entries.contains { $0.hasSuffix(".xctest") || $0.hasSuffix(".a") || $0.hasSuffix(".o") }
        return hasModules && hasBinary
    }

    /// Root under which this run may create scratch directories.
    ///
    /// * default `swift test`  -> `<pkg>/.build/…/Debug` resolves up to `<pkg>/.build`
    /// * `--scratch-path A/build/root` -> resolves up to `A/build/root`
    ///
    /// Both cases are found by locating the nearest ancestor that owns the build
    /// products, never by matching a hard-coded directory name.
    public static func scratchRoot() throws -> URL {
        let products = try productsDirectory()
        var location = products
        // SwiftPM layouts place products at <scratch>/<triple>/debug,
        // <scratch>/debug or <scratch>/out/Products/Debug. Walk up to the scratch root
        // by looking for the directory that holds SwiftPM's own bookkeeping.
        for _ in 0..<6 {
            let parent = location.deletingLastPathComponent()
            if parent.path == location.path { break }
            if isScratchRoot(location) { return location }
            location = parent
        }
        if isScratchRoot(location) { return location }
        // Fall back to the products directory itself: still isolated, still per-run.
        return products
    }

    private static func isScratchRoot(_ directory: URL) -> Bool {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory.path) else { return false }
        return entries.contains("workspace-state.json") || entries.contains("manifest.pif")
            || entries.contains("CACHEDIR.TAG")
    }

    /// A fresh, isolated, canonicalized scratch directory inside this run's scratch root.
    public static func scratchDirectory(label: String = "test-scratch") throws -> URL {
        let root = try scratchRoot()
        let directory = root.appendingPathComponent("\(label)/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resolved = canonical(directory)
        let resolvedRoot = canonical(root)
        guard resolved.path == resolvedRoot.path
                || resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw LocatorError.pathEscapesScratchRoot(path: resolved.path, root: resolvedRoot.path)
        }
        return resolved
    }

    /// Validates a path that claims to be an executable probe. Used so a missing or
    /// non-executable probe reports a harness fault instead of a product failure.
    public static func validateProbe(at url: URL) throws -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { throw LocatorError.probeMissing(url.path) }
        guard manager.isExecutableFile(atPath: url.path) else {
            throw LocatorError.probeNotExecutable(url.path)
        }
        return canonical(url)
    }
}
