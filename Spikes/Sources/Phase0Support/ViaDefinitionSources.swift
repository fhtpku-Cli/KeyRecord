import Foundation

public struct ViaDefinitionSource: Codable, Equatable, Sendable {
    public let repository: String
    public let commit: String
    public let tree: String
    public let path: String
    public let gitBlob: String
    public let sha256: String
    public let licensePath: String
    public let licenseBlob: String
    public let licenseSha256: String
}

public enum ViaDefinitionSources {
    public static let v2 = ViaDefinitionSource(
        repository: "https://github.com/the-via/app.git",
        commit: "65b50efc8e14e6feabff38ce20c191edf1f078f9",
        tree: "9d76a3b8a5b7ec976c3ef9048c49caa09779e25b",
        path: "evidence/phase0/sources/repos/via-app/files/src/utils/test-keyboard-definition.json",
        gitBlob: "8e89dd0f5103c5b7e15f43eaab785ef4ad6a62f3",
        sha256: "b42bea649bde12804e6ddd5d872b63dbb4d8b5a228ad8814b9d44856e136921a",
        licensePath: "evidence/phase0/sources/repos/via-app/license/LICENSE",
        licenseBlob: "f288702d2fa16d3cdf0035b15a9fcbc552cd88e7",
        licenseSha256: "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
    )

    public static let v3 = ViaDefinitionSource(
        repository: "https://github.com/the-via/keyboards.git",
        commit: "e44d80f991664a9676a9a53fbb41892d88ef9069",
        tree: "fc8161d0a33e7a46c60953afa484ed2ce919bd1e",
        path: "evidence/phase0/sources/repos/via-keyboards/files/v3/0_sixty/0_sixty.json",
        gitBlob: "7ec91dd24b29c68e5fa975469b304a03c6bc136a",
        sha256: "914df98445330205bddaa1dbec142865ef1e3d6063eb93b02c6c72545c923f19",
        licensePath: "evidence/phase0/sources/repos/via-keyboards/license/LICENSE",
        licenseBlob: "f288702d2fa16d3cdf0035b15a9fcbc552cd88e7",
        licenseSha256: "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
    )
}

public enum ViaDefinitionDigest {
    public static func sha256(_ data: Data) -> String { AtomicityDigest.sha256(data) }
}
