import Foundation

public enum HostOperation: String, Codable, CaseIterable, Sendable {
    case keychain = "keychain-create/delete-test-items"
    case screen = "screen-lock/unlock"
    case sleep = "sleep/wake"
    case restart
    case capture = "packet-capture"
}

public struct HostManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let hostID: String
    public let architecture: String
    public let macOS: String
    public let certificateSHA256: String
    public let teamID: String
    public let bundleIDs: [String]
    public let namespacePrefix: String
    public let scratchRoot: String
    public let operations: [HostOperation]
    public let expiresAt: String
    public let controllerPath: String
    public let controllerSHA256: String
    public let attemptID: String

    private enum Field: String, CodingKey, CaseIterable {
        case schemaVersion, hostID, architecture, macOS, certificateSHA256, teamID, bundleIDs
        case namespacePrefix, scratchRoot, operations, expiresAt, controllerPath, controllerSHA256, attemptID
    }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Key.self)
        guard Set(keys.allKeys.map(\.stringValue)) == Set(Field.allCases.map(\.rawValue)) else {
            throw PreflightBlock.malformedManifest
        }
        let c = try decoder.container(keyedBy: Field.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        hostID = try c.decode(String.self, forKey: .hostID)
        architecture = try c.decode(String.self, forKey: .architecture)
        macOS = try c.decode(String.self, forKey: .macOS)
        certificateSHA256 = try c.decode(String.self, forKey: .certificateSHA256)
        teamID = try c.decode(String.self, forKey: .teamID)
        bundleIDs = try c.decode([String].self, forKey: .bundleIDs)
        namespacePrefix = try c.decode(String.self, forKey: .namespacePrefix)
        scratchRoot = try c.decode(String.self, forKey: .scratchRoot)
        operations = try c.decode([HostOperation].self, forKey: .operations)
        expiresAt = try c.decode(String.self, forKey: .expiresAt)
        controllerPath = try c.decode(String.self, forKey: .controllerPath)
        controllerSHA256 = try c.decode(String.self, forKey: .controllerSHA256)
        attemptID = try c.decode(String.self, forKey: .attemptID)
    }
}

public struct HostIdentity: Sendable {
    public let hostID: String
    public let architecture: String
    public let macOS: String
    public let certificateSHA256: String
    public let teamID: String
    public let bundleIDs: [String]
    public let signatureValid: Bool
    public let entitlementsValid: Bool
}

public struct PreflightContext: Sendable {
    public let identity: HostIdentity
    public let attemptID: String
    public let scratchRoot: String
    public let controllerSHA256: String
    public let controllerExecutable: Bool

    public func replacingIdentity(_ value: HostIdentity) -> Self {
        Self(identity: value, attemptID: attemptID, scratchRoot: scratchRoot,
             controllerSHA256: controllerSHA256, controllerExecutable: controllerExecutable)
    }
}

public enum PreflightBlock: String, Error, Sendable {
    case missingManifest, malformedManifest, expired, hostMismatch, signature, entitlement
    case namespace, scratchRoot, operation, controller, attemptMismatch, unavailableIdentity
}

public enum PreflightVerdict: Equatable, Sendable {
    case ready
    case blocked(PreflightBlock)
    public var exitStatus: Int32 {
        switch self { case .ready: 0; case .blocked: 2 }
    }
}
