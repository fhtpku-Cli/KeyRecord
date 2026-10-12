import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class CandidateConstraintTests: XCTestCase {
    private func chord(_ code: Int, command: ModifierSideState = .none, shift: ModifierSideState = .none) throws -> Chord {
        Chord(keyCode: try KeyCode(code), modifiers: ModifierSet(command: command, option: .none,
            control: .none, shift: shift, fn: .none))
    }

    private func input(backend: BackendConnection, scope: RecommendationScope = .global,
                       layout: LayoutPreference = LayoutPreference(), pool: Set<KeyCode> = []) throws -> CandidateCheckInput {
        CandidateCheckInput(source: try chord(8, command: .left, shift: .left), trigger: try chord(122),
            scope: scope, backend: backend, layout: layout, keyboardPool: pool)
    }

    func testFiveReadinessStatesKeepPartialChecksExplicit() throws {
        let connected = BackendConnection.connected(BackendCapabilities(backend: .karabiner,
            keyCodes: [try KeyCode(8), try KeyCode(122)], applicationScope: true, fnModifier: false))
        XCTAssertEqual(CandidateConstraints.assess(try input(backend: .disconnected(.karabiner))), .disconnected)
        XCTAssertEqual(CandidateConstraints.assess(try input(backend: .unsupported(.karabiner))), .unsupported(.backend))
        let request = try input(backend: connected)
        XCTAssertEqual(CandidateConstraints.assess(request), .unchecked)
        let conflict = CandidateConflictCheck(input: request, conflicts: [.existingRuleOverlap], evidenceKinds: ["karabiner-overlap"])
        XCTAssertEqual(CandidateConstraints.assess(request, check: conflict), .conflict([.existingRuleOverlap]))
        let checked = CandidateConflictCheck(input: request, conflicts: [], evidenceKinds: ["observed"])
        XCTAssertEqual(CandidateConstraints.assess(request, check: checked), .checked(evidenceKinds: ["observed"]))
        XCTAssertEqual(CandidateConstraints.assess(request,
            check: CandidateConflictCheck(input: request, conflicts: [], evidenceKinds: [])), .unchecked)
    }

    func testScopeLayoutPoolAndBackendChangesInvalidateChecks() throws {
        let caps = BackendCapabilities(backend: .karabiner, keyCodes: [try KeyCode(8), try KeyCode(122)], applicationScope: true, fnModifier: false)
        let request = try input(backend: .connected(caps))
        let checked = CandidateConflictCheck(input: request, conflicts: [], evidenceKinds: ["observed"])
        let changed = try [input(backend: .connected(caps), scope: .application("app.editor")),
            input(backend: .connected(caps), layout: LayoutPreference(preset: .ansi, hasAsked: true)),
            input(backend: .connected(caps), pool: [KeyCode(122)]),
            input(backend: .connected(BackendCapabilities(backend: .via, keyCodes: [KeyCode(8), KeyCode(122)], applicationScope: true, fnModifier: false)))]
        for item in changed { XCTAssertEqual(CandidateConstraints.assess(item, check: checked), .unchecked) }
        let newTrigger = CandidateCheckInput(source: request.source, trigger: try chord(120), scope: .global,
            backend: .connected(BackendCapabilities(backend: .karabiner, keyCodes: [try KeyCode(8), try KeyCode(122), try KeyCode(120)], applicationScope: true, fnModifier: false)))
        XCTAssertEqual(CandidateConstraints.assess(newTrigger, check: checked), .unchecked)
        let changedEvidence = CandidateCheckInput(source: request.source, trigger: request.trigger, scope: request.scope,
            backend: request.backend, physicalEvidence: PhysicalEvidence(geometry: nil, chain: [], device: .unknown, scope: .global))
        XCTAssertEqual(CandidateConstraints.assess(changedEvidence, check: checked), .unchecked)
    }

    func testBackendConstraintsAndStatefulSourceCannotBeBypassed() throws {
        let caps = BackendCapabilities(backend: .via, keyCodes: [try KeyCode(8), try KeyCode(122)], applicationScope: false, fnModifier: false)
        XCTAssertEqual(CandidateConstraints.assess(try input(backend: .connected(caps), scope: .application("app.editor"))), .unsupported(.applicationScope))
        let request = CandidateCheckInput(source: try chord(48, command: .left), trigger: try chord(122), scope: .global,
            backend: .connected(caps))
        XCTAssertEqual(CandidateConstraints.assess(request), .unsupported(.stateful))
        let missingKey = BackendCapabilities(backend: .via, keyCodes: [], applicationScope: false, fnModifier: false)
        XCTAssertEqual(CandidateConstraints.assess(try input(backend: .connected(missingKey))), .unsupported(.keyCode))
        let fnTrigger = Chord(keyCode: try KeyCode(122), modifiers: ModifierSet(command: .none, option: .none,
            control: .none, shift: .none, fn: .active))
        XCTAssertEqual(CandidateConstraints.assess(CandidateCheckInput(source: try chord(8, command: .left),
            trigger: fnTrigger, scope: .global, backend: .connected(caps))), .unsupported(.fnModifier))
    }

    func testBareAndShiftPrintableRequireConfirmationAndCancelClearsDraft() throws {
        var draft = ManualCandidateDraft()
        let plain = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        try draft.propose(keyCode: "0", modifiers: plain)
        XCTAssertEqual(draft.state, .awaitingRiskConfirmation(try chord(0)))
        draft.invalidate()
        draft.confirmRisk()
        XCTAssertEqual(draft.state, .editing)
        try draft.propose(keyCode: "0", modifiers: plain)
        draft.confirmRisk()
        XCTAssertEqual(draft.state, .accepted(try chord(0)))
        try draft.propose(keyCode: "0", modifiers: ModifierSet(command: .none, option: .none, control: .none, shift: .left, fn: .none))
        XCTAssertEqual(draft.state, .awaitingRiskConfirmation(try chord(0, shift: .left)))
    }

    func testSourceOutputKeyAndFnAreRequiredEvenWhenTriggerIsSupported() throws {
        let source = Chord(keyCode: try KeyCode(8), modifiers: ModifierSet(command: .left, option: .none,
            control: .none, shift: .none, fn: .active))
        let trigger = try chord(122)
        let triggerOnly = BackendCapabilities(backend: .karabiner, keyCodes: [trigger.keyCode], applicationScope: true, fnModifier: true)
        let missingSource = CandidateCheckInput(source: source, trigger: trigger, scope: .global, backend: .connected(triggerOnly))
        let falsePass = CandidateConflictCheck(input: missingSource, conflicts: [], evidenceKinds: ["observed"])
        XCTAssertEqual(CandidateConstraints.assess(missingSource, check: falsePass), .unsupported(.keyCode))
        let noFn = BackendCapabilities(backend: .karabiner, keyCodes: [source.keyCode, trigger.keyCode], applicationScope: true, fnModifier: false)
        let missingFn = CandidateCheckInput(source: source, trigger: trigger, scope: .global, backend: .connected(noFn))
        XCTAssertEqual(CandidateConstraints.assess(missingFn,
            check: CandidateConflictCheck(input: missingFn, conflicts: [], evidenceKinds: ["observed"])), .unsupported(.fnModifier))
        let supportsBoth = BackendCapabilities(backend: .karabiner, keyCodes: [source.keyCode, trigger.keyCode], applicationScope: true, fnModifier: true)
        let valid = CandidateCheckInput(source: source, trigger: trigger, scope: .global, backend: .connected(supportsBoth))
        XCTAssertEqual(CandidateConstraints.assess(valid,
            check: CandidateConflictCheck(input: valid, conflicts: [], evidenceKinds: ["observed"])), .checked(evidenceKinds: ["observed"]))
    }

    func testInvalidKeyUnknownModifiersAndOngoingChordClearOldAcceptance() throws {
        var draft = ManualCandidateDraft()
        let plain = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        try draft.propose(keyCode: "122", modifiers: plain)
        XCTAssertEqual(draft.state, .accepted(try chord(122)))
        for code in ["52", "127", "-1", "macro", "55"] {
            XCTAssertThrowsError(try draft.propose(keyCode: code, modifiers: plain))
            XCTAssertEqual(draft.state, .editing)
        }
        XCTAssertThrowsError(try draft.propose(keyCode: "122", modifiers: ModifierSet()))
        XCTAssertThrowsError(try draft.propose(keyCode: "48", modifiers:
            ModifierSet(command: .left, option: .none, control: .none, shift: .none, fn: .none)))
        XCTAssertEqual(draft.state, .editing)
    }
}
