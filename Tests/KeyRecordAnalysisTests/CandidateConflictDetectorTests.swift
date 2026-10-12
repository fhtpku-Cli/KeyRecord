import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class CandidateConflictDetectorTests: XCTestCase {
    func testLargeEvidenceProducesDeterministicScopedResults() throws {
        let observations = try (0..<10_000).map { index in
            ChordBucket(chord: try chord(index % 26), appBucket: .bundleID("synthetic.app.\(index)"))
        }
        let rules = try (0..<2_000).map { index in
            BackendRule(trigger: try chord(index % 26), output: try chord((index + 1) % 26), profile: "p")
        }
        let request = try input(observations: observations, rules: rules)
        let clock = ContinuousClock()
        let started = clock.now
        let result = CandidateConflictDetector.evaluate(request)
        print("B conflict check: observations=10000 rules=2000 elapsed=\(started.duration(to: clock.now))")
        XCTAssertEqual(result, CandidateConflictDetector.evaluate(request))
        XCTAssertTrue(result.findings.isEmpty)
    }

    private func chord(_ key: Int, command: ModifierSideState = .none, shift: ModifierSideState = .none) throws -> Chord {
        Chord(keyCode: try KeyCode(key), modifiers: ModifierSet(command: command, option: .none,
            control: .none, shift: shift, fn: .none))
    }

    private func input(source: Chord? = nil, trigger: Chord? = nil, scope: RecommendationScope = .global,
        observations: [ChordBucket]? = [], rules: [BackendRule] = [], origin: BackendEvidenceOrigin = .currentAdapter,
        unsupported: Int = 0, devices: Set<String>? = nil, profile: String = "p", protected: Set<Chord> = []) throws -> CandidateCheckInput {
        let capabilities = BackendCapabilities(backend: .karabiner, keyCodes: Set((0...126).compactMap { try? KeyCode($0) }), applicationScope: true, fnModifier: true)
        return CandidateCheckInput(source: try source ?? chord(8, command: .left, shift: .left),
            trigger: try trigger ?? chord(122), scope: scope, backend: .connected(capabilities),
            conflictEvidence: CandidateConflictEvidence(observations: observations,
                backendRules: BackendRuleEvidence(backend: .karabiner, profile: "p", rules: rules,
                    unsupportedRuleCount: unsupported, origin: origin, protectedTriggers: protected, backendVersion: "synthetic-v1"),
                profile: profile, devices: devices))
    }

    func testObservedConflictsRespectScopeAndKeepUnknownAttributionIncomplete() throws {
        let trigger = try chord(122)
        let rows = [ChordBucket(chord: trigger, appBucket: .bundleID("app.other"))]
        XCTAssertEqual(CandidateConflictDetector.evaluate(try input(observations: rows)).findings.map(\.kind), [.observedShortcut])
        XCTAssertTrue(CandidateConflictDetector.evaluate(try input(scope: .application("app.editor"), observations: rows)).findings.isEmpty)
        let unknown = CandidateConflictDetector.evaluate(try input(scope: .application("app.editor"),
            observations: [ChordBucket(chord: trigger, appBucket: .unknown)]))
        XCTAssertEqual(unknown.readiness, .unchecked)
        XCTAssertTrue(unknown.limitations.contains(.unknownApplication))
        let sideUnknown = try chord(8, command: .activeSideUnknown)
        let report = CandidateConflictDetector.evaluate(try input(trigger: chord(8, command: .left),
            observations: [ChordBucket(chord: sideUnknown, appBucket: .bundleID("app.editor"))]))
        XCTAssertEqual(report.findings.first?.severity, .warning)
    }

    func testSystemTriggerRiskIsSeparateFromSourceClassification() throws {
        let report = CandidateConflictDetector.evaluate(try input(trigger: chord(20, command: .right, shift: .right)))
        XCTAssertEqual(report.findings.map(\.kind), [.knownSystemRisk])
        XCTAssertEqual(report.findings.first?.severity, .warning)
    }

    func testMissingCopyAndUnsupportedEvidenceNeverBecomeChecked() throws {
        for request in try [input(observations: nil), input(origin: .selectedCopy), input(unsupported: 1), input(profile: "other")] {
            XCTAssertEqual(CandidateConflictDetector.evaluate(request).readiness, .unchecked)
        }
        let current = CandidateConflictDetector.evaluate(try input())
        XCTAssertEqual(current.readiness, .checked(evidenceKinds: ["observed", "known-system-risk", "karabiner-overlap"]))
        XCTAssertEqual(current.limitations, [.menuUnavailable])
        let disconnected = CandidateCheckInput(source: try chord(8, command: .left), trigger: try chord(122),
            scope: .global, backend: .disconnected(.karabiner))
        XCTAssertEqual(CandidateConflictDetector.evaluate(disconnected).readiness, .disconnected)
    }

    func testRuleOverlapUsesProfileScopeDeviceAndModifierDomains() throws {
        let rule = BackendRule(trigger: try chord(122), output: try chord(120), scope: .application("app.editor"), devices: ["keyboard-a"], profile: "p")
        let match = CandidateConflictDetector.evaluate(try input(scope: .application("app.editor"), rules: [rule], devices: ["keyboard-a"]))
        XCTAssertEqual(match.findings.map(\.kind), [.existingRuleOverlap])
        XCTAssertEqual(match.findings.first?.severity, .blocking)
        for request in try [input(scope: .application("app.other"), rules: [rule]), input(rules: [rule], devices: ["keyboard-b"]),
            input(rules: [BackendRule(trigger: chord(122), output: nil, profile: "other")]),
            input(trigger: chord(122, command: .left), rules: [rule])] {
            XCTAssertTrue(CandidateConflictDetector.evaluate(request).findings.isEmpty)
        }
    }

    func testCycleRequiresACommonScopeAndDeviceForTheWholePath() throws {
        let a = try chord(8, command: .left, shift: .left), b = try chord(120), c = try chord(122)
        let first = BackendRule(trigger: a, output: b, scope: .application("app.a"), devices: ["a"], profile: "p")
        let second = BackendRule(trigger: b, output: c, scope: .application("app.a"), devices: ["a"], profile: "p")
        XCTAssertEqual(CandidateConflictDetector.evaluate(try input(rules: [first, second])).findings.map(\.kind), [.mappingCycle])
        let disjointApp = BackendRule(trigger: b, output: c, scope: .application("app.b"), devices: ["a"], profile: "p")
        let disjointDevice = BackendRule(trigger: b, output: c, scope: .application("app.a"), devices: ["b"], profile: "p")
        XCTAssertTrue(CandidateConflictDetector.evaluate(try input(rules: [first, disjointApp])).findings.isEmpty)
        XCTAssertTrue(CandidateConflictDetector.evaluate(try input(rules: [first, disjointDevice])).findings.isEmpty)
    }

    func testProtectedEntriesAndNewEvidenceWithdrawPriorChecks() throws {
        let request = try input()
        let previous = CandidateConflictDetector.evaluate(request).check
        let protected = try input(protected: [chord(122)])
        XCTAssertEqual(CandidateConstraints.assess(protected, check: previous), .unchecked)
        XCTAssertEqual(CandidateConflictDetector.evaluate(protected).findings.map(\.kind), [.protectedLayerEntry])
        let changed = try input(observations: [ChordBucket(chord: chord(122), appBucket: .unknown)])
        XCTAssertEqual(CandidateConstraints.assess(changed, check: previous), .unchecked)
        let oldEvidence = try XCTUnwrap(request.conflictEvidence)
        let missingVersion = CandidateCheckInput(source: request.source, trigger: request.trigger, scope: request.scope,
            backend: request.backend, conflictEvidence: CandidateConflictEvidence(observations: [],
                backendRules: BackendRuleEvidence(backend: .karabiner, profile: "p", rules: [], origin: .currentAdapter), profile: "p"))
        XCTAssertEqual(CandidateConflictDetector.evaluate(missingVersion).readiness, .unchecked)
        let newVersion = CandidateCheckInput(source: request.source, trigger: request.trigger, scope: request.scope,
            backend: request.backend, conflictEvidence: CandidateConflictEvidence(observations: oldEvidence.observations,
                backendRules: BackendRuleEvidence(backend: .karabiner, profile: "p", rules: [], origin: .currentAdapter,
                    backendVersion: "synthetic-v2"), profile: "p"))
        XCTAssertEqual(CandidateConstraints.assess(newVersion, check: previous), .unchecked)
    }

    func testCapabilitiesFilterBeforeTruncationAndRequireSourceSupport() throws {
        let source = try chord(8, command: .left, shift: .left)
        let confirmed = Set(try [122,120,99,118,96].map(KeyCode.init))
        let caps = BackendCapabilities(backend: .karabiner, keyCodes: [source.keyCode, try KeyCode(122)], applicationScope: true, fnModifier: true)
        let triggers = LogicalPreviews.generate(source, confirmed: confirmed, capabilities: caps)
        XCTAssertTrue(triggers.contains { $0.chord.keyCode.value == 122 })
        XCTAssertLessThanOrEqual(triggers.count, 3)
        XCTAssertFalse(triggers.contains { [96,99,118,120].contains($0.chord.keyCode.value) })
        let noSource = BackendCapabilities(backend: .via, keyCodes: confirmed, applicationScope: false, fnModifier: false)
        XCTAssertTrue(LogicalPreviews.generate(source, confirmed: confirmed, capabilities: noSource).isEmpty)
    }
}
