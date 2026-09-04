import Foundation
import XCTest
@testable import Phase0Support

final class KarabinerSpikeTests: XCTestCase {
    private let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testUpstreamValidSchemaAndAdversarialInvalidSchema() throws {
        let valid = try upstream("valid.json")
        XCTAssertNoThrow(try KarabinerManagedBlockPlanner.inspect(valid))
        for name in ["broken.json", "rules_error.json", "type_error.json"] {
            XCTAssertThrowsError(try KarabinerManagedBlockPlanner.inspect(try upstream(name)), name)
        }
    }

    func testInsertUpdateClearAndRestorePreserveBytesOutsideManagedBlock() throws {
        let base = try upstream("valid.json")
        let rules = try ruleObjects(count: 3)
        let inserted = try KarabinerManagedBlockPlanner.plan(base: base, baselineSHA256: digest(base), rules: rules)
        XCTAssertEqual(inserted.ruleCount, 3)
        assertOutsideBytesPreserved(inserted)

        let updated = try KarabinerManagedBlockPlanner.plan(base: inserted.bytes, baselineSHA256: digest(inserted.bytes), rules: [rules[1]])
        XCTAssertEqual(updated.ruleCount, 1)
        assertOutsideBytesPreserved(updated)

        let cleared = try KarabinerManagedBlockPlanner.plan(base: updated.bytes, baselineSHA256: digest(updated.bytes), rules: [])
        XCTAssertEqual(cleared.ruleCount, 0)
        assertOutsideBytesPreserved(cleared)

        let restored = try KarabinerManagedBlockPlanner.plan(base: cleared.bytes, baselineSHA256: digest(cleared.bytes), rules: rules)
        XCTAssertEqual(restored.ruleCount, 3)
        assertOutsideBytesPreserved(restored)
    }

    func testDuplicateAndMalformedBlocksReject() throws {
        let base = try upstream("valid.json")
        let one = try KarabinerManagedBlockPlanner.plan(base: base, baselineSHA256: digest(base), rules: [])
        let inspection = try KarabinerManagedBlockPlanner.inspect(one.bytes)
        let block = one.bytes.subdata(in: inspection.managedRange!)
        let closing = inspection.rulesArrayRange.upperBound - 1
        var duplicate = Data(one.bytes.prefix(closing))
        duplicate.append(Data(",\n        ".utf8)); duplicate.append(block); duplicate.append(one.bytes.suffix(one.bytes.count - closing))
        XCTAssertThrowsError(try KarabinerManagedBlockPlanner.inspect(duplicate)) {
            XCTAssertEqual($0 as? KarabinerManagedBlockError, .malformedManagedBlock)
        }
        let malformed = Data(String(decoding: one.bytes, as: UTF8.self)
            .replacingOccurrences(of: KarabinerManagedBlock.endDescription, with: "not-an-end-marker").utf8)
        XCTAssertThrowsError(try KarabinerManagedBlockPlanner.inspect(malformed)) {
            XCTAssertEqual($0 as? KarabinerManagedBlockError, .malformedManagedBlock)
        }
    }

    func testBaselineMismatchAndExternalEditNeverProduceOverwriteBytes() throws {
        let base = try upstream("valid.json")
        XCTAssertThrowsError(try KarabinerManagedBlockPlanner.plan(base: base, baselineSHA256: String(repeating: "0", count: 64), rules: [])) {
            XCTAssertEqual($0 as? KarabinerManagedBlockError, .baselineMismatch)
        }
        let result = KarabinerRecovery.classify(
            currentSHA256: String(repeating: "e", count: 64),
            hBase: String(repeating: "a", count: 64),
            hExpect: String(repeating: "b", count: 64),
            rollbackRequested: true
        )
        XCTAssertEqual(result, .externalChangeRefusal)
        XCTAssertNil(result.bytesToWrite(beforeImage: base))
    }

    func testEveryCrashBoundaryMapsToHExpectHBaseOrExternalWithoutAutomaticExternalWrite() {
        let hBase = String(repeating: "a", count: 64)
        let hExpect = String(repeating: "b", count: 64)
        for boundary in AtomicReplacementCrashBoundary.allCases {
            let current = boundary.isAfterRename ? hExpect : hBase
            XCTAssertEqual(KarabinerRecovery.classify(currentSHA256: current, hBase: hBase, hExpect: hExpect, rollbackRequested: false), boundary.isAfterRename ? .finishCommit : .markFailedNoWrite)
        }
        XCTAssertEqual(KarabinerRecovery.classify(currentSHA256: String(repeating: "c", count: 64), hBase: hBase, hExpect: hExpect, rollbackRequested: false), .externalChangeRefusal)
    }

    func testRollbackWritesBeforeImageOnlyFromHExpectBranch() throws {
        let before = try upstream("valid.json")
        let hBase = digest(before), hExpect = String(repeating: "b", count: 64)
        let rollback = KarabinerRecovery.classify(currentSHA256: hExpect, hBase: hBase, hExpect: hExpect, rollbackRequested: true)
        XCTAssertEqual(rollback, .rollbackBeforeImage)
        XCTAssertEqual(rollback.bytesToWrite(beforeImage: before), before)
        XCTAssertNil(KarabinerRecovery.classify(currentSHA256: hBase, hBase: hBase, hExpect: hExpect, rollbackRequested: true).bytesToWrite(beforeImage: before))
    }

    func testUnknownAndDescriptionNotesVersionBoundary() {
        XCTAssertFalse(KarabinerVersionGate(version: nil).writeSupported)
        XCTAssertFalse(KarabinerVersionGate(version: "unknown").writeSupported)
        XCTAssertFalse(KarabinerVersionGate(version: "16.1.22").supportsDescriptionNotes)
        XCTAssertTrue(KarabinerVersionGate(version: "16.1.23").supportsDescriptionNotes)
        XCTAssertTrue(KarabinerVersionGate(version: "17.0.0").supportsDescriptionNotes)
    }

    func testParserBoundsRejectLargeAndDeepUntrustedInputs() throws {
        XCTAssertThrowsError(try KarabinerManagedBlockPlanner.inspect(Data(repeating: 0x20, count: KarabinerManagedBlockPlanner.maximumBytes + 1)))
        let deep = Data((String(repeating: "[", count: KarabinerManagedBlockPlanner.maximumDepth + 1) + String(repeating: "]", count: KarabinerManagedBlockPlanner.maximumDepth + 1)).utf8)
        XCTAssertThrowsError(try KarabinerManagedBlockPlanner.inspect(deep))
    }

    private func assertOutsideBytesPreserved(_ plan: KarabinerManagedBlockPlan, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(plan.bytes.prefix(plan.replacementRange.lowerBound), plan.base.prefix(plan.replacementRange.lowerBound), file: file, line: line)
        let newSuffix = plan.bytes.suffix(plan.base.count - plan.replacementRange.upperBound)
        XCTAssertEqual(newSuffix, plan.base.suffix(plan.base.count - plan.replacementRange.upperBound), file: file, line: line)
    }

    private func upstream(_ name: String) throws -> Data {
        try Data(contentsOf: repository.appendingPathComponent("evidence/phase0/sources/repos/karabiner/files/tests/src/complex_modifications_assets/json/lint/assets/\(name)"))
    }
    private func ruleObjects(count: Int) throws -> [Data] {
        let root = try JSONSerialization.jsonObject(with: upstream("valid.json")) as! [String: Any]
        return try (root["rules"] as! [Any]).prefix(count).enumerated().map { index, value in
            var object = value as! [String: Any]; object["description"] = "KeyRecord fixture rule \(index + 1)"
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } + (count == 3 ? [try JSONSerialization.data(withJSONObject: (root["rules"] as! [Any])[0], options: [.sortedKeys])] : [])
    }
    private func digest(_ data: Data) -> String { AtomicityDigest.sha256(data) }
}
