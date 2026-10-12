import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class PhysicalAnalysisTests: XCTestCase {
    private var source: Chord {
        get throws { Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left, option: .none, control: .none, shift: .left, fn: .none)) }
    }
    private var trigger: Chord {
        get throws { Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)) }
    }

    private func fixture(target: [String] = ["cmd", "far"], secondFrame: String = "board") throws -> PhysicalEvidence {
        let geometry = try CanonicalGeometry(positions: [
            PhysicalPosition(id: "cmd", centerX: 0, centerY: 0, coordinateFrame: "board"),
            PhysicalPosition(id: "near", centerX: 1, centerY: 0, coordinateFrame: "board"),
            PhysicalPosition(id: "c", centerX: 2, centerY: 0, coordinateFrame: "board"),
            PhysicalPosition(id: "far", centerX: 8, centerY: 0, coordinateFrame: secondFrame)])
        let a: [PhysicalToken] = [.hidUsage(0xe3), .hidUsage(0xe1), .hidUsage(0x06)]
        let b: [PhysicalToken] = [.hidUsage(0xe3), .hidUsage(0x06)]
        let outputA: [PhysicalToken] = try [.observedKey(KeyCode(55)), .observedKey(KeyCode(56)), .observedKey(KeyCode(8))]
        let outputB: [PhysicalToken] = try [.observedKey(KeyCode(55)), .observedKey(KeyCode(8))]
        return PhysicalEvidence(geometry: geometry, chain: [
            TransformEvidence(link: .firmware, status: .verified, reference: "synthetic:firmware", mapping: CanonicalTransform(mappings: [
                .init(input: ["cmd", "near", "c"].map(PhysicalToken.position), output: a),
                .init(input: target.map(PhysicalToken.position), output: b)], completeInverseFor: [a, b])),
            TransformEvidence(link: .software, status: .verified, reference: "synthetic:software", mapping: CanonicalTransform(mappings: [
                .init(input: a, output: a), .init(input: b, output: b)], completeInverseFor: [a, b])),
            TransformEvidence(link: .macOS, status: .verified, reference: "synthetic:macos", mapping: CanonicalTransform(mappings: [
                .init(input: a, output: outputA), .init(input: b, output: outputB)], completeInverseFor: [outputA, outputB]))
        ], device: .singleVerified, scope: .global)
    }

    private func compare(_ evidence: PhysicalEvidence?) throws -> PhysicalCostComparison {
        try PhysicalAnalysis.compare(source: source, trigger: trigger, scope: .global, evidence: evidence)
    }

    func testFewerPressesCanHaveLargerDiameter() throws {
        let result = try compare(fixture())
        guard case .physical(let a, let b) = result else { return XCTFail("Expected synthetic physical comparison") }
        XCTAssertEqual(a.pressCount, 3)
        XCTAssertEqual(b.pressCount, 2)
        XCTAssertEqual(a.positionDiameter, 2)
        XCTAssertEqual(b.positionDiameter, 8)
        XCTAssertEqual(b.positionDiameter - a.positionDiameter, 6)
    }

    func testRepeatedPressesAreCountedAndSourceOnlySuccessCannotMixUnits() throws {
        guard case .physical(_, let cost) = try compare(fixture(target: ["near", "near"])) else { return XCTFail("Expected repeated gesture") }
        XCTAssertEqual(cost.pressCount, 2)
        XCTAssertEqual(cost.positionDiameter, 0)
        let complete = try fixture()
        let first = try XCTUnwrap(complete.chain.first)
        let mapping = try XCTUnwrap(first.mapping)
        let partial = CanonicalTransform(mappings: [mapping.mappings[0]], completeInverseFor: mapping.completeInverseFor)
        let bad = PhysicalEvidence(geometry: complete.geometry, chain: [
            TransformEvidence(link: .firmware, status: .verified, reference: first.reference, mapping: partial),
            complete.chain[1], complete.chain[2]], device: .singleVerified, scope: .global)
        XCTAssertEqual(try compare(bad), .logical(sourceKeys: 3, triggerKeys: 2, reason: .noAction))
    }

    func testPartialInverseCoverageAndAmbiguityCannotBeVerifiedByOneMatch() throws {
        let complete = try fixture()
        let first = complete.chain[0]
        let mapping = try XCTUnwrap(first.mapping)
        let cases: [(CanonicalTransform, PhysicalFallbackReason)] = [
            (CanonicalTransform(mappings: mapping.mappings, completeInverseFor: []), .incompleteInverseCoverage),
            (CanonicalTransform(mappings: mapping.mappings + [.init(input: [.position("far")], output: mapping.mappings[0].output)],
                                completeInverseFor: mapping.completeInverseFor), .ambiguousAction)]
        for (changed, reason) in cases {
            let evidence = PhysicalEvidence(geometry: complete.geometry, chain: [TransformEvidence(link: .firmware, status: .verified,
                reference: first.reference, mapping: changed), complete.chain[1], complete.chain[2]], device: .singleVerified, scope: .global)
            XCTAssertEqual(try compare(evidence), .logical(sourceKeys: 3, triggerKeys: 2, reason: reason))
        }
    }

    func testMissingChangedDeviceScopeAndGeometryReasonsStayExplicit() throws {
        let complete = try fixture()
        XCTAssertEqual(try compare(nil), .logical(sourceKeys: 3, triggerKeys: 2, reason: .missingEvidence))
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: nil, chain: complete.chain, device: .singleVerified, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .missingGeometry))
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: complete.chain, device: .multiDeviceUncertain, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .deviceUncertain))
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: complete.chain, device: .singleVerified, scope: .application("app.editor"))),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .scopeMismatch))
        let changed = TransformEvidence(link: .software, status: .externallyChanged, reference: complete.chain[1].reference,
                                        mapping: complete.chain[1].mapping)
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: [complete.chain[0], changed, complete.chain[2]], device: .singleVerified, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .unavailableTransform(.software, .externallyChanged)))
        XCTAssertEqual(try compare(fixture(secondFrame: "unpositioned-half")),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .incomparableGeometry))
    }

    func testEmptyIdentityChainAndInvalidStageNamespacesCannotStandInForEvidence() throws {
        let complete = try fixture()
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: [], device: .singleVerified, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .incompleteChain))
        let swapped = [complete.chain[1], complete.chain[0], complete.chain[2]]
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: swapped, device: .singleVerified, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .incompleteChain))
        let wrong = TransformEvidence(link: .firmware, status: .verified, reference: "synthetic:wrong",
            mapping: CanonicalTransform(mappings: [.init(input: [.observedKey(try KeyCode(8))], output: [.hidUsage(0x06)])],
                                        completeInverseFor: []))
        XCTAssertEqual(try compare(PhysicalEvidence(geometry: complete.geometry, chain: [wrong, complete.chain[1], complete.chain[2]], device: .singleVerified, scope: .global)),
                       .logical(sourceKeys: 3, triggerKeys: 2, reason: .invalidTransform))
    }

    func testGeometryRejectsDuplicateAndNonfinitePositions() throws {
        let p = try PhysicalPosition(id: "one", centerX: 0, centerY: 0, coordinateFrame: "board")
        XCTAssertThrowsError(try CanonicalGeometry(positions: [p, p]))
        XCTAssertThrowsError(try PhysicalPosition(id: "one", centerX: .infinity, centerY: 0, coordinateFrame: "board"))
    }
}
