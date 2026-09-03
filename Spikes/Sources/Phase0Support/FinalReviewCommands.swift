import Foundation

public struct FinalReviewCommandRegistry: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reviewers: [ReviewerCommands]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case schemaVersion, reviewers }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "FinalReviewCommandRegistry")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        reviewers = try values.decode([ReviewerCommands].self, forKey: .reviewers)
    }
}

public struct ReviewerCommands: Codable, Equatable, Sendable {
    public let reviewerID: String
    public let commands: [RegisteredCommand]

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case reviewerID, commands }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "ReviewerCommands")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reviewerID = try values.decode(String.self, forKey: .reviewerID)
        commands = try values.decode([RegisteredCommand].self, forKey: .commands)
    }
}

public struct RegisteredCommand: Codable, Equatable, Sendable {
    public let id: String
    public let argv: [String]
    public let expectedExitStatus: Int32

    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case id, argv, expectedExitStatus }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "RegisteredCommand")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        argv = try values.decode([String].self, forKey: .argv)
        expectedExitStatus = try values.decode(Int32.self, forKey: .expectedExitStatus)
    }
}
