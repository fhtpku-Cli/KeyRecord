import Foundation

public enum Phase0PrivacyError: Error, Equatable, Sendable {
    case forbiddenField(String, String)
    case forbiddenText(String)
    case invalidJSON(String)
    case invalidPath(String)
    case invalidTextEncoding(String)
    case nonRegularFile(String)
    case resourceLimit(String)
    case symlink(String)
    case unmarkedEventRecord(String)
}

public struct Phase0PrivacyReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let filesScanned: Int
    public let jsonFilesScanned: Int
    public let forbiddenHitCount: Int
    public let symlinkCount: Int
    public let unmarkedEventRecordCount: Int
    public let conclusionGenerated: Bool

    public init(filesScanned: Int, jsonFilesScanned: Int, conclusionGenerated: Bool = false) {
        schemaVersion = 1
        self.filesScanned = filesScanned
        self.jsonFilesScanned = jsonFilesScanned
        forbiddenHitCount = 0
        symlinkCount = 0
        unmarkedEventRecordCount = 0
        self.conclusionGenerated = conclusionGenerated
    }
}

public enum Phase0PrivacyAudit {
    public static let maximumFileBytes = 4 * 1_024 * 1_024
    public static let maximumTotalBytes = 16 * 1_024 * 1_024
    public static let maximumFiles = 256
    public static let maximumJSONDepth = 64
    public static let maximumJSONCollection = 4_096
    public static let maximumJSONScalarBytes = 1_024 * 1_024
    private static let maximumJSONNodes = 100_000
    private static let forbiddenFields = [
        "serial", "serialnumber", "credential", "credentials", "username", "keytext", "keysequence",
        "keystream", "eventsequence", "exacttimestamp", "keychain", "keychainitem",
        "password", "accesstoken", "apikey", "authorization",
    ]
    private static let textMarkers = [
        "/users/", "/home/", "~/", "ignore validation", "ignore all previous",
        "report pass", "prompt injection",
    ]
    public static func scan(root: URL, excluding: Set<String> = []) throws -> Phase0PrivacyReport {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [], errorHandler: nil
        ) else { throw Phase0PrivacyError.invalidPath(root.path) }
        var fileCount = 0
        var jsonCount = 0
        var totalBytes = 0
        var normalizedPaths = Set<String>()
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let relative = String(file.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
                throw Phase0PrivacyError.invalidPath(relative)
            }
            let normalized = relative.precomposedStringWithCanonicalMapping
            guard normalizedPaths.insert(normalized).inserted else { throw Phase0PrivacyError.invalidPath(relative) }
            if values.isSymbolicLink == true { throw Phase0PrivacyError.symlink(relative) }
            guard values.isRegularFile == true else { continue }
            guard !excluding.contains(relative) else { continue }
            fileCount += 1
            guard fileCount <= maximumFiles else { throw Phase0PrivacyError.resourceLimit(relative) }
            let ext = file.pathExtension.lowercased()
            let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
            guard bytes.count <= maximumFileBytes, totalBytes <= maximumTotalBytes - bytes.count else {
                throw Phase0PrivacyError.resourceLimit(relative)
            }
            totalBytes += bytes.count
            if relative == "sp6b/build/argon2-universal.a" {
                guard AtomicityDigest.sha256(bytes) == "95497a26d620d235fd8c1da64dcd6cd08830a5090c9c0266b33af22ad899b110" else {
                    throw Phase0PrivacyError.invalidTextEncoding(relative)
                }
                continue
            }
            if ext == "json" {
                jsonCount += 1
                do { try scanJSON(bytes, path: relative) }
                catch Phase0PrivacyError.invalidJSON { try scanText(bytes, path: relative) }
            } else {
                try scanText(bytes, path: relative)
            }
        }
        return Phase0PrivacyReport(
            filesScanned: fileCount,
            jsonFilesScanned: jsonCount,
            conclusionGenerated: FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path)
        )
    }

    public static func scanJSON(_ bytes: Data, path: String) throws {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: bytes) }
        catch { throw Phase0PrivacyError.invalidJSON(path) }
        var nodes = 0
        try inspect(object, path: path, depth: 0, nodes: &nodes)
        try scanText(bytes, path: path)
    }

    public static func scanText(_ bytes: Data, path: String) throws {
        guard bytes.count <= maximumFileBytes else { throw Phase0PrivacyError.resourceLimit(path) }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw Phase0PrivacyError.invalidTextEncoding(path)
        }
        let lower = text.lowercased()
        if textMarkers.contains(where: lower.contains) { throw Phase0PrivacyError.forbiddenText(path) }
    }

    private static func inspect(_ value: Any, path: String, depth: Int, nodes: inout Int) throws {
        guard depth <= maximumJSONDepth, nodes < maximumJSONNodes else {
            throw Phase0PrivacyError.resourceLimit(path)
        }
        nodes += 1
        if let object = value as? [String: Any] {
            guard object.count <= maximumJSONCollection,
                  object.keys.allSatisfy({ $0.utf8.count <= maximumJSONScalarBytes }) else {
                throw Phase0PrivacyError.resourceLimit(path)
            }
            let normalizedKeys = Set(object.keys.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
            let fieldKeys = Set(normalizedKeys.map { $0.filter(\.isLetter) })
            if let field = fieldKeys.first(where: forbiddenFields.contains) {
                throw Phase0PrivacyError.forbiddenField(path, field)
            }
            let eventKey = object.keys.first { $0.precomposedStringWithCanonicalMapping.lowercased().filter(\.isLetter) == "keycode" }
            if let eventKey, object[eventKey] is NSNumber {
                let marker = (object["marker"] as? NSNumber)?.uint64Value
                guard marker == ProductSyntheticMarker.value else {
                    throw Phase0PrivacyError.unmarkedEventRecord(path)
                }
            }
            for key in object.keys { try scanText(Data(key.utf8), path: path) }
            for child in object.values { try inspect(child, path: path, depth: depth + 1, nodes: &nodes) }
        } else if let array = value as? [Any] {
            guard array.count <= maximumJSONCollection else { throw Phase0PrivacyError.resourceLimit(path) }
            for child in array { try inspect(child, path: path, depth: depth + 1, nodes: &nodes) }
        } else if let text = value as? String {
            guard text.utf8.count <= maximumJSONScalarBytes else { throw Phase0PrivacyError.resourceLimit(path) }
            try scanText(Data(text.utf8), path: path)
        }
    }
}
