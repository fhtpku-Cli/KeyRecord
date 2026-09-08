import Foundation
import XCTest
@testable import Phase0Support

final class InputObservationTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)
    private let commit = String(repeating: "b", count: 40)
    private let tree = String(repeating: "c", count: 40)

    func testProductStampedKeyDownKeyUpAndFlagsChangedAreRecordedThenDropped() throws {
        var observer = InputObservationState()
        for kind in InputEventKind.allCases {
            try observer.observe(.init(kind: kind, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value))
        }
        XCTAssertEqual(observer.aggregateCount, 0)
        XCTAssertEqual(observer.productStampedRecords.map(\.kind), InputEventKind.allCases)
        XCTAssertTrue(observer.productStampedRecords.allSatisfy(\.dropped))
    }

    func testMalformedSyntheticMarkerRejectsAndUnmarkedDetailsDoNotPersist() throws {
        var observer = InputObservationState()
        XCTAssertThrowsError(try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: 1)))
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        XCTAssertEqual(observer.aggregateCount, 1)
        XCTAssertTrue(observer.productStampedRecords.isEmpty)
    }

    func testAutoRepeatProducesOneLogicalCount() throws {
        var observer = InputObservationState()
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: true, marker: nil))
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: true, marker: nil))
        try observer.observe(.init(kind: .keyUp, keyCode: 4, isAutoRepeat: false, marker: nil))
        XCTAssertEqual(observer.aggregateCount, 1)
    }

    func testTapResetIncrementsGenerationAndClosesGate() throws {
        var observer = InputObservationState()
        XCTAssertEqual(observer.generation, 0)
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        XCTAssertEqual(observer.aggregateCount, 1)
        observer.tapDisabled()
        XCTAssertEqual(observer.generation, 1)
        XCTAssertFalse(observer.gateOpen)
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        XCTAssertEqual(observer.aggregateCount, 1)
        observer.rebuildTap()
        XCTAssertTrue(observer.gateOpen)
        try observer.observe(.init(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil))
        XCTAssertEqual(observer.aggregateCount, 2, "reset must clear the key that was held before the tap was disabled")
    }

    func testPersistedInputObservationModelsRejectUnknownFields() throws {
        try assertUnknownFieldRejects(SyntheticInputEvent(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: nil), as: SyntheticInputEvent.self)
        try assertUnknownFieldRejects(ProductStampedRecord(kind: .keyDown, keyCode: 4, isAutoRepeat: false, marker: ProductSyntheticMarker.value, dropped: true), as: ProductStampedRecord.self)
        try assertUnknownFieldRejects(SP1LiveAggregateArtifact(systemShortcutObservedCount: 0, unmarkedObservedCount: 0), as: SP1LiveAggregateArtifact.self)
    }

    func testO7GuaranteeIsConservative() {
        XCTAssertEqual(O7Boundary.classify(marker: ProductSyntheticMarker.value, hasInjectionIndicator: true), .productTest)
        XCTAssertEqual(O7Boundary.classify(marker: nil, hasInjectionIndicator: true), .suspectedSynthetic)
        XCTAssertEqual(O7Boundary.classify(marker: nil, hasInjectionIndicator: false), .ordinaryObserved)
        XCTAssertTrue(O7Boundary.guarantee.contains("only product-stamped"))
        XCTAssertTrue(O7Boundary.guarantee.contains("suspected, never proven"))
    }

    func testCompletePassingIdentityAndMatrixValidate() throws { XCTAssertNoThrow(try validReport().validate()) }

    func testTapSelectionPrefersSessionWhenBothMatricesPass() {
        XCTAssertEqual(SP1TapSelection.select(sessionPasses: true, annotatedPasses: true), "session")
        XCTAssertEqual(SP1TapSelection.select(sessionPasses: false, annotatedPasses: true), "annotated")
        XCTAssertNil(SP1TapSelection.select(sessionPasses: false, annotatedPasses: false))
    }

    func testBothMatricesPassingWithSessionSelectionValidates() throws {
        var report = validReport()
        report.schemaVersion = 3
        let annotated = report.legs.firstIndex(where: { $0.legID == "sp1.tap.annotated.matrix" })!
        report.legs[annotated].verdict = .pass
        report.legs[annotated].blocker = nil
        report.legs[annotated].identity = nil
        report.legs[annotated].matrix = .init(
            offObservedCode: 79, offCount: 1, onObservedCode: 80, onCount: 1,
            expectedPhysicalCode: 79, expectedTransformedCode: 80
        )
        XCTAssertNoThrow(try report.validate())
    }
    func testDuplicateObservationRejects() { assertReject(.duplicateLeg, mutate(validReport()) { $0.legs.append($0.legs[0]) }) }
    func testMissingObservationRejects() { assertReject(.missingLeg, mutate(validReport()) { $0.legs.removeLast() }) }
    func testTCCDeniedProducesCompleteBlockedRecordsAndNoSelection() throws { XCTAssertNoThrow(try blockedReport(tcc: false, karabiner: true).validate()) }
    func testKarabinerAbsentProducesCompleteBlockedRecordsAndNoSelection() throws { XCTAssertNoThrow(try blockedReport(tcc: true, karabiner: false).validate()) }
    func testSessionAnnotatedIdentityMixRejects() { assertIdentityMismatch(\.tapType, "annotated") }
    func testAttemptIdentityMixRejects() { assertIdentityMismatch(\.attemptID, "other") }
    func testRunnerCommitIdentityMixRejects() { assertIdentityMismatch(\.runnerCommitSha, String(repeating: "d", count: 40)) }
    func testRunnerTreeIdentityMixRejects() { assertIdentityMismatch(\.runnerTreeSha, String(repeating: "d", count: 40)) }
    func testEnvironmentIdentityMixRejects() { assertIdentityMismatch(\.environmentSha256, String(repeating: "d", count: 64)) }
    func testTapConfigIdentityMixRejects() { assertIdentityMismatch(\.tapConfigSha256, String(repeating: "e", count: 64)) }
    func testEvidenceReuseRejects() {
        let report = mutate(validReport()) { $0.legs[3].artifactSha256 = $0.legs[2].artifactSha256 }
        assertReject(.reusedEvidence, report)
    }
    func testNoSelectionFailOutranksBlocked() {
        var report = blockedReport(tcc: false, karabiner: false)
        let index = report.legs.startIndex
        report.legs[index].verdict = .fail
        report.legs[index].detectorAvailable = true
        report.legs[index].blocker = nil
        report.legs[index].artifactSha256 = String(repeating: "f", count: 64)
        assertReject(.invalidAggregate, report)
        report.verdict = .fail
        XCTAssertNoThrow(try report.validate())
    }

    func testNoSelectionInconclusiveOutranksPass() {
        var report = blockedReport(tcc: false, karabiner: false)
        for index in report.legs.indices {
            let matrix = report.legs[index].legID.hasPrefix("sp1.tap.")
            report.legs[index].verdict = matrix || index == report.legs.startIndex ? .inconclusive : .pass
            report.legs[index].detectorAvailable = true
            report.legs[index].blocker = nil
            report.legs[index].artifactSha256 = String(format: "%064x", index + 20)
        }
        report.verdict = .inconclusive
        XCTAssertNoThrow(try report.validate())
    }

    func testNoSelectionBlockedOutranksInconclusive() {
        var report = blockedReport(tcc: false, karabiner: false)
        for index in report.legs.indices.dropFirst() {
            report.legs[index].verdict = .inconclusive
            report.legs[index].detectorAvailable = true
            report.legs[index].blocker = nil
            report.legs[index].artifactSha256 = String(format: "%064x", index + 40)
        }
        XCTAssertNoThrow(try report.validate())
        report.verdict = .inconclusive
        assertReject(.invalidAggregate, report)
    }

    func testSelectedTapAggregationIncludesAncillaryAndExcludesNonselectedTap() {
        var report = validReport()
        let ancillary = report.legs.firstIndex(where: { $0.legID == "sp1.autoRepeat" })!
        report.legs[ancillary].verdict = .fail
        report.verdict = .fail
        XCTAssertNoThrow(try report.validate())
        let nonselected = report.legs.firstIndex(where: { $0.legID == "sp1.tap.annotated.matrix" })!
        report.legs[nonselected].verdict = .blocked
        report.legs[nonselected].detectorAvailable = false
        report.legs[nonselected].blocker = SP1Blocker(blockedBy: "not_selected", detectCommand: ["fixture"], prerequisite: "candidate", unblockAction: "rerun")
        report.legs[nonselected].artifactSha256 = nil
        XCTAssertNoThrow(try report.validate())
    }
    func testDuplicateAndMissingMatrixCountsRejectPass() {
        assertReject(.invalidMatrix, mutate(validReport()) { report in report.legs[report.legs.firstIndex(where: { $0.legID == "sp1.tap.session.matrix" })!].matrix = .init(offObservedCode: 4, offCount: 2, onObservedCode: 5, onCount: 1, expectedPhysicalCode: 4, expectedTransformedCode: 5) })
        assertReject(.invalidMatrix, mutate(validReport()) { report in report.legs[report.legs.firstIndex(where: { $0.legID == "sp1.tap.session.matrix" })!].matrix = .init(offObservedCode: 4, offCount: 1, onObservedCode: nil, onCount: 0, expectedPhysicalCode: 4, expectedTransformedCode: 5) })
    }

    private func identity(tapType: String = "session", attempt: String = "attempt", runnerCommit: String? = nil, runnerTree: String? = nil, environment: String? = nil, config: String? = nil) -> SelectedTapIdentity {
        .init(tapType: tapType, attemptID: attempt, runnerCommitSha: runnerCommit ?? commit, runnerTreeSha: runnerTree ?? tree, environmentSha256: environment ?? sha, tapConfigSha256: config ?? String(repeating: "d", count: 64))
    }

    private func validReport() -> SP1Evidence {
        let id = identity()
        let ids = SP1Evidence.requiredLegIDs.sorted()
        let legs = ids.enumerated().map { index, legID in
            SP1Leg(legID: legID, verdict: legID == "sp1.tap.annotated.matrix" ? .fail : .pass, detectorAvailable: true, blocker: nil, identity: legID == "sp1.tap.annotated.matrix" ? nil : id, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: sha, artifactSha256: String(format: "%064x", index + 1), matrix: legID == "sp1.tap.session.matrix" ? .init(offObservedCode: 4, offCount: 1, onObservedCode: 5, onCount: 1, expectedPhysicalCode: 4, expectedTransformedCode: 5) : nil, aggregateCount: legID == "sp1.systemShortcut" ? 1 : nil)
        }
        return .init(selectedTapIdentity: id, legs: legs, verdict: .pass, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": sha])
    }

    private func blockedReport(tcc: Bool, karabiner: Bool) -> SP1Evidence {
        let blocker = SP1Blocker(blockedBy: tcc ? "karabiner_absent" : "input_monitoring_denied", detectCommand: ["safe-preflight"], prerequisite: "required prerequisite", unblockAction: "Grant or install separately, then rerun")
        let legs = SP1Evidence.requiredLegIDs.sorted().map { id in
            SP1Leg(legID: id, verdict: .blocked, detectorAvailable: false, blocker: blocker, identity: nil, runnerCommitSha: commit, runnerTreeSha: tree, environmentSha256: sha, artifactSha256: nil, matrix: nil, aggregateCount: nil)
        }
        return .init(selectedTapIdentity: nil, legs: legs, verdict: .blocked, g0Status: .open, o7Guarantee: O7Boundary.guarantee, runnerSourceSha256: ["source": sha])
    }

    private func assertIdentityMismatch(_ keyPath: WritableKeyPath<SelectedTapIdentity, String>, _ value: String) {
        let report = mutate(validReport()) { report in report.legs[report.legs.firstIndex(where: { $0.legID == "sp1.autoRepeat" })!].identity?[keyPath: keyPath] = value }
        assertReject(.mixedIdentity, report)
    }
    private func assertReject(_ expected: SP1ValidationError, _ report: SP1Evidence) {
        XCTAssertThrowsError(try report.validate()) { XCTAssertEqual($0 as? SP1ValidationError, expected) }
    }
    private func assertUnknownFieldRejects<T: Codable>(_ value: T, as type: T.Type, file: StaticString = #filePath, line: UInt = #line) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["unexpected"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object)), file: file, line: line)
    }
    private func mutate(_ value: SP1Evidence, _ body: (inout SP1Evidence) -> Void) -> SP1Evidence { var copy = value; body(&copy); return copy }
}
