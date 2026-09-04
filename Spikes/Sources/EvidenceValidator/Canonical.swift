import CryptoKit
import Foundation

enum Canonical {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func pathDigest(files: [(path: String, data: Data)]) throws -> String {
        var normalized = Set<String>()
        var rows: [(Data, String)] = []
        for file in files {
            let path = file.path.precomposedStringWithCanonicalMapping
            guard normalized.insert(path).inserted else { throw ValidatorError("normalization_collision", path) }
            guard let pathData = path.data(using: .utf8) else { throw ValidatorError("invalid_path_encoding", path) }
            rows.append((pathData, sha256(file.data)))
        }
        rows.sort { $0.0.lexicographicallyPrecedes($1.0) }
        var stream = Data()
        for (path, hash) in rows {
            stream.append(path)
            stream.append(0)
            stream.append(Data(hash.utf8))
            stream.append(10)
        }
        return sha256(stream)
    }
}

extension URL {
    func relativePath(from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { throw ValidatorError("path_outside_repository", path) }
        return String(path.dropFirst(prefix.count))
    }
}
