import Foundation

public struct SP5BSourceAnchor: Codable, Equatable, Sendable {
    public let repository: String
    public let revision: String
    public let tree: String
    public let path: String
    public let gitBlob: String
    public let fileSha256: String
    public let lineStart: Int
    public let lineEnd: Int
    public let snippetSha256: String
    public let licensePath: String
    public let licenseGitBlob: String
    public let licenseSha256: String
}

public struct SP5BWhitelistCase: Codable, Equatable, Sendable {
    public let caseID: String
    public let opcode: String
    public let packetLayout: String
    public let responseLayout: String
    public let anchors: [SP5BSourceAnchor]
}

public struct SP5BSourceFactsArtifact: Codable, Equatable, Sendable {
    public let whitelist: [SP5BWhitelistCase]
    public let denyAllDefault: Bool
    public let reportDescription: String
    public let publicCases: [String]
    public let reportSourcePath: String
    public let reportSourceSha256: String
    public let noPublicRawBytesInitializer: Bool
    public let excludedOperationFamilies: [String]
}

public struct SP5BReplayArtifact: Codable, Equatable, Sendable {
    public let fixtureKind: String
    public let fixturePath: String
    public let fixtureSha256: String
    public let protocolVersion: UInt32
    public let uid: String
    public let definitionByteCount: Int
    public let definitionSha256: String
    public let keymapHex: String
    public let keymapKeycodes: [UInt16]
    public let reportHex: [String]
    public let responseSha256: [String]
    public let reportCount: Int
    public let timeoutMilliseconds: Int
    public let maximumDefinitionBytes: Int
    public let maximumKeymapBytes: Int
    public let maximumKeymapChunkBytes: Int
}

public struct SP5BDeniedAttempt: Codable, Equatable, Sendable {
    public let name: String
    public let opcode: String
    public let rejected: Bool
    public let transportCallCount: Int
}

public struct SP5BDenyMutationArtifact: Codable, Equatable, Sendable {
    public let attempts: [SP5BDeniedAttempt]
    public let sourceContractValidated: Bool
    public let publicCases: [String]
    public let noRawReportEscapeHatch: Bool
    public let denyAllDefault: Bool
}
