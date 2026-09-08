import XCTest
@testable import Phase0Support

final class SP2LiveAggregateV2ReducerTests: XCTestCase {
    private let excludedIDs: Set<String> = ["app.excluded"]

    func testTerminalKeyDownCountsOnlyReliableFrontmostFamilies() {
        var reducer = SP2LiveAggregateV2Reducer()
        for frontmost in SP2FrontmostAttribution.allCases {
            reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .disabled, frontmost: frontmost)
        }
        let aggregate = reducer.aggregate
        XCTAssertEqual(aggregate.knownAttributable, 1)
        XCTAssertEqual(aggregate.knownUnattributable, 1)
        XCTAssertEqual(aggregate.tapResets, 0)
        XCTAssertEqual(aggregate.fnUnknownAfterReset, 0)
        XCTAssertEqual(aggregate.fnRecoveredKnownNone, 0)
        XCTAssertEqual(aggregate.fnRecoveredKnownActive, 0)
        XCTAssertNoThrow(try aggregate.validate())
    }

    func testGateClosedKeyDownProducesNoCounterUpdates() {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: false, secureInput: .enabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: false, secureInput: .disabled, frontmost: .knownAttributable)
        XCTAssertEqual(reducer.aggregate, SP2LiveAggregateV2())
        XCTAssertNoThrow(try reducer.aggregate.validate())
    }

    func testSecureInputEnabledAndUnknownProduceNoCounterUpdates() {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .enabled, frontmost: .knownAttributable)
        reducer.recordTerminalKeyDown(gateOpen: true, secureInput: .unknown, frontmost: .knownAttributable)
        XCTAssertEqual(reducer.aggregate, SP2LiveAggregateV2())
        XCTAssertNoThrow(try reducer.aggregate.validate())
    }

    func testTapResetCountsResetsOnly() {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordTapReset()
        reducer.recordTapReset()
        let aggregate = reducer.aggregate
        XCTAssertEqual(aggregate.tapResets, 2)
        XCTAssertEqual(aggregate.knownAttributable + aggregate.knownUnattributable, 0)
        XCTAssertEqual(aggregate.fnUnknownAfterReset + aggregate.fnRecoveredKnownNone + aggregate.fnRecoveredKnownActive, 0)
        XCTAssertNoThrow(try aggregate.validate())
    }

    func testFnRecoverySnapshotCountsBothRecoveredStatesExactlyOnce() {
        var reducer = SP2LiveAggregateV2Reducer()
        reducer.recordFnRecoverySnapshot(.knownNone)
        reducer.recordFnRecoverySnapshot(.knownActive)
        let aggregate = reducer.aggregate
        XCTAssertEqual(aggregate.fnRecoveredKnownNone, 1)
        XCTAssertEqual(aggregate.fnRecoveredKnownActive, 1)
        XCTAssertEqual(aggregate.fnUnknownAfterReset, 0)
        XCTAssertNoThrow(try aggregate.validate())
    }

    func testParityWithPrivacyTransitionModelDecisions() {
        let contexts: [FrontmostState] = [
            .known(bundleID: "app.allowed"), .known(bundleID: "app.excluded"), .known(bundleID: ""),
            .knownUnattributable, .indeterminate,
        ]
        for context in contexts {
            for secure in SecureInputState.allCases {
                var model = PrivacyTransitionModel()
                var reducer = SP2LiveAggregateV2Reducer()
                let gateOpen = model.gateOpen
                let decision = model.observeTerminalKeyDown(frontmost: context, secureInput: secure, excludedBundleIDs: excludedIDs)
                reducer.recordTerminalKeyDown(gateOpen: gateOpen, secureInput: secure, frontmost: attribution(for: context))
                let aggregate = reducer.aggregate
                let counted = aggregate.knownAttributable + aggregate.knownUnattributable
                XCTAssertEqual(counted, model.totals.data, "\(context) \(secure)")
                XCTAssertEqual(counted, model.totals.meta, "\(context) \(secure)")
                switch decision {
                case .counted(bucket: .bundle):
                    XCTAssertEqual(aggregate.knownAttributable, 1, "\(context) \(secure)")
                    XCTAssertEqual(aggregate.knownUnattributable, 0, "\(context) \(secure)")
                case .counted(bucket: .unknown):
                    XCTAssertEqual(aggregate.knownUnattributable, 1, "\(context) \(secure)")
                    XCTAssertEqual(aggregate.knownAttributable, 0, "\(context) \(secure)")
                case .dropped:
                    XCTAssertEqual(aggregate, SP2LiveAggregateV2(), "\(context) \(secure)")
                }
            }
        }
    }

    func testParityAcrossGateCloseTapResetAndRebuildLifecycle() {
        var model = PrivacyTransitionModel()
        var reducer = SP2LiveAggregateV2Reducer()
        XCTAssertEqual(observe(&model, &reducer), .counted(bucket: .bundle("app.allowed")))
        model.captureState = .paused
        XCTAssertEqual(observe(&model, &reducer), .dropped)
        model.captureState = .collecting
        XCTAssertEqual(model.tapReset(), .zero)
        reducer.recordTapReset()
        XCTAssertEqual(observe(&model, &reducer), .dropped)
        model.recoverTap()
        XCTAssertEqual(observe(&model, &reducer), .counted(bucket: .bundle("app.allowed")))
        XCTAssertEqual(model.systemWillSleep(), .zero)
        XCTAssertEqual(observe(&model, &reducer), .dropped)
        model.systemDidWake()
        XCTAssertEqual(observe(&model, &reducer), .dropped)
        model.recoverAfterWake()
        XCTAssertEqual(observe(&model, &reducer), .counted(bucket: .bundle("app.allowed")))
        let aggregate = reducer.aggregate
        XCTAssertEqual(aggregate.knownAttributable, 3)
        XCTAssertEqual(aggregate.tapResets, 1)
        XCTAssertEqual(aggregate.knownAttributable, model.totals.data)
        XCTAssertNoThrow(try aggregate.validate())
    }

    func testFnRecoveryParityWithModifierReconstructionModel() {
        var modifiers = ModifierReconstructionModel()
        var reducer = SP2LiveAggregateV2Reducer()
        modifiers.applyFn(active: true)
        modifiers.invalidate(for: .eventLoss)
        XCTAssertEqual(modifiers.fn, .unknown)
        reducer.recordFnRecoverySnapshot(modifiers.fn)
        modifiers.applyFn(active: true)
        reducer.recordFnRecoverySnapshot(modifiers.fn)
        modifiers.invalidate(for: .tapReset)
        XCTAssertEqual(modifiers.fn, .unknown)
        reducer.recordFnRecoverySnapshot(modifiers.fn)
        modifiers.applyFn(active: false)
        reducer.recordFnRecoverySnapshot(modifiers.fn)
        let aggregate = reducer.aggregate
        XCTAssertEqual(aggregate.fnUnknownAfterReset, 2)
        XCTAssertEqual(aggregate.fnRecoveredKnownActive, 1)
        XCTAssertEqual(aggregate.fnRecoveredKnownNone, 1)
        XCTAssertNoThrow(try aggregate.validate())
    }

    @discardableResult
    private func observe(
        _ model: inout PrivacyTransitionModel,
        _ reducer: inout SP2LiveAggregateV2Reducer,
        frontmost: FrontmostState = .known(bundleID: "app.allowed"),
        secure: SecureInputState = .disabled
    ) -> PrivacyDecision {
        let gateOpen = model.gateOpen
        let decision = model.observeTerminalKeyDown(frontmost: frontmost, secureInput: secure, excludedBundleIDs: excludedIDs)
        reducer.recordTerminalKeyDown(gateOpen: gateOpen, secureInput: secure, frontmost: attribution(for: frontmost))
        return decision
    }

    private func attribution(for state: FrontmostState) -> SP2FrontmostAttribution {
        switch state {
        case let .known(bundleID):
            return !bundleID.isEmpty && !excludedIDs.contains(bundleID) ? .knownAttributable : .excluded
        case .knownUnattributable:
            return .knownUnattributable
        case .indeterminate:
            return .indeterminate
        }
    }
}
