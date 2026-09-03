import CryptoKit
import Foundation
import XCTest
@testable import Phase0Support

final class ProvenanceTests: XCTestCase {
    func testPinnedSourceLedgerUsesExactFullRevisionsAndTrees() {
        XCTAssertEqual(PinnedSourceLedger.entries.count, 9)
        XCTAssertEqual(PinnedSourceLedger.entries.map(\.commit), [
            "865f0e0ee6ebb5f6a6857058b0cbfab8297f8469",
            "65b50efc8e14e6feabff38ce20c191edf1f078f9",
            "e44d80f991664a9676a9a53fbb41892d88ef9069",
            "cfdff9d8404547f55e0128ff278ea237c8a39bee",
            "3c73e928ab40b026adcff7112c8fc36a8d96152a",
            "dd43959ae5c08d8a28d38a1acf7b04e86b14a344",
            "aef8222a2d0429a183b2ed692d5f9efcfd383f08",
            "f57e61e19229e23c4445b85494dbf7c07de721cb",
            "14d47de1914ac63b368ddb2cfe0f47ffe25f04cf",
        ])
        XCTAssertEqual(PinnedSourceLedger.entries.map(\.tree), [
            "10a85f02a5aa381e8e1523bb25df314a29b6cfa0",
            "9d76a3b8a5b7ec976c3ef9048c49caa09779e25b",
            "fc8161d0a33e7a46c60953afa484ed2ce919bd1e",
            "5d057dd5439729f195b0e177b06363fbdcb44f2b",
            "12276f044f5c8aa2a96075cb72c5d2c2d89955fe",
            "b9a0d7b574d78f3e0622c5cfe1f9ff9901d63f64",
            "22a59cd7c2f7c4ef746378e259f6de0f1faa3633",
            "ac3dc753ff75ce5a0f243cba1d94582bafe09409",
            "4bb860f4c47b4b327ea207da3fe7a007a05c7b81",
        ])
        XCTAssertTrue(PinnedSourceLedger.entries.allSatisfy { $0.commit.count == 40 && $0.tree.count == 40 })
    }

    func testSyntheticFixturesHaveExactBytesHashesAndNoTrailingNewline() {
        for fixture in SyntheticFixtureLedger.entries {
            let data = Data(fixture.bytes.utf8)
            XCTAssertFalse(data.last == 0x0a)
            XCTAssertEqual(SHA256.hash(data: data).hex, fixture.sha256)
        }
        XCTAssertEqual(SyntheticFixtureLedger.via.sha256, "4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800")
        XCTAssertEqual(SyntheticFixtureLedger.vial.sha256, "61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3")
    }

    func testProvenanceRejectsSHAAndGitBlobDrift() throws {
        let original = Data("untrusted source bytes".utf8)
        let expected = ProvenanceDigest(
            sha256: SHA256.hash(data: original).hex,
            gitBlob: GitBlobHasher.sha1Hex(for: original)
        )
        XCTAssertNoThrow(try ProvenanceValidator.validate(original, expected: expected))

        var mutated = original
        mutated.append(0x0a)
        XCTAssertThrowsError(try ProvenanceValidator.validate(mutated, expected: expected))
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
