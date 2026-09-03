import CryptoKit
import Foundation

public struct PinnedSource: Equatable, Sendable {
    public let name: String
    public let commit: String
    public let tree: String
}

public enum PinnedSourceLedger {
    public static let entries = [
        PinnedSource(name: "karabiner", commit: "865f0e0ee6ebb5f6a6857058b0cbfab8297f8469", tree: "10a85f02a5aa381e8e1523bb25df314a29b6cfa0"),
        PinnedSource(name: "via-app", commit: "65b50efc8e14e6feabff38ce20c191edf1f078f9", tree: "9d76a3b8a5b7ec976c3ef9048c49caa09779e25b"),
        PinnedSource(name: "via-keyboards", commit: "e44d80f991664a9676a9a53fbb41892d88ef9069", tree: "fc8161d0a33e7a46c60953afa484ed2ce919bd1e"),
        PinnedSource(name: "via-docs", commit: "cfdff9d8404547f55e0128ff278ea237c8a39bee", tree: "5d057dd5439729f195b0e177b06363fbdcb44f2b"),
        PinnedSource(name: "qmk", commit: "3c73e928ab40b026adcff7112c8fc36a8d96152a", tree: "12276f044f5c8aa2a96075cb72c5d2c2d89955fe"),
        PinnedSource(name: "vial-qmk", commit: "dd43959ae5c08d8a28d38a1acf7b04e86b14a344", tree: "b9a0d7b574d78f3e0622c5cfe1f9ff9901d63f64"),
        PinnedSource(name: "vial-gui", commit: "aef8222a2d0429a183b2ed692d5f9efcfd383f08", tree: "22a59cd7c2f7c4ef746378e259f6de0f1faa3633"),
        PinnedSource(name: "phc-argon2", commit: "f57e61e19229e23c4445b85494dbf7c07de721cb", tree: "ac3dc753ff75ce5a0f243cba1d94582bafe09409"),
        PinnedSource(name: "swift-argon2id", commit: "14d47de1914ac63b368ddb2cfe0f47ffe25f04cf", tree: "4bb860f4c47b4b327ea207da3fe7a007a05c7b81"),
    ]
}

public struct SyntheticFixture: Equatable, Sendable {
    public let filename: String
    public let bytes: String
    public let sha256: String
}

public enum SyntheticFixtureLedger {
    public static let via = SyntheticFixture(
        filename: "via-layout.json",
        bytes: #"{"name":"phase0-layout","vendorProductId":1980457056,"layers":[["KC_A","KC_B"],["KC_C","KC_D"]],"macros":[""],"encoders":[]}"#,
        sha256: "4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800"
    )
    public static let vial = SyntheticFixture(
        filename: "phase0.vil",
        bytes: #"{"version":1,"uid":"0000000000000000","layout":[["KC_A","KC_B"]],"encoder_layout":[],"layout_options":0,"macro":[""],"vial_protocol":6,"via_protocol":9,"tap_dance":[],"combo":[],"key_override":[],"alt_repeat_key":[],"settings":{}}"#,
        sha256: "61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3"
    )
    public static let entries = [via, vial]
}

public struct ProvenanceDigest: Equatable, Sendable {
    public let sha256: String
    public let gitBlob: String

    public init(sha256: String, gitBlob: String) {
        self.sha256 = sha256
        self.gitBlob = gitBlob
    }
}

public enum ProvenanceError: Error, Equatable { case sha256Drift, gitBlobDrift }

public enum ProvenanceValidator {
    public static func validate(_ data: Data, expected: ProvenanceDigest) throws {
        let sha256 = SHA256.hash(data: data).hex
        guard sha256 == expected.sha256 else { throw ProvenanceError.sha256Drift }
        guard GitBlobHasher.sha1Hex(for: data) == expected.gitBlob else { throw ProvenanceError.gitBlobDrift }
    }
}

public enum GitBlobHasher {
    public static func sha1Hex(for data: Data) -> String {
        var framed = Data("blob \(data.count)\u{0}".utf8)
        framed.append(data)
        return Insecure.SHA1.hash(data: framed).hex
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
