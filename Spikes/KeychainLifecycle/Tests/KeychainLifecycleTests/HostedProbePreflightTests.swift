import Foundation
import XCTest
@testable import LifecyclePreflight

final class HostedProbePreflightTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testHappyValidReadOnlyPreflight() throws {
        // Given
        let fixture = PreflightFixture()
        let counter = EffectCounter()
        // When
        let verdict = Preflight.evaluate(data: try fixture.data(), context: fixture.context, now: now)
        // Then
        XCTAssertEqual(verdict, .ready)
        XCTAssertEqual(counter.keychain, 0)
        XCTAssertEqual(counter.controller, 0)
    }

    func testFailureManifestMatrixHasZeroEffects() throws {
        // Given: every fixture differs from the independently supplied live identity.
        let fixture = PreflightFixture()
        let changes: [(String, String)] = [
            ("expiresAt", "2000-01-01T00:00:00Z"), ("hostID", "other-host"),
            ("teamID", "OTHERTEAM"), ("architecture", "x86_64"),
            ("macOS", "0.0"), ("namespacePrefix", "com.keyrecord.app"),
            ("scratchRoot", "/outside"), ("controllerSHA256", String(repeating: "b", count: 64)),
            ("certificateSHA256", String(repeating: "c", count: 64)),
            ("attemptID", "replayed"), ("expiresAt", "not-a-date"),
        ]
        for (field, value) in changes {
            let counter = EffectCounter()
            // When: exercise's gate is the same gate used before each signed SecItem call.
            let result = try PreflightFixture.gatedEffects(data: fixture.data(changing: field, to: value),
                                                         context: fixture.context, counter: counter, now: now)
            // Then
            XCTAssertEqual(result.exitStatus, 2, field)
            XCTAssertEqual(counter.keychain, 0, field)
            XCTAssertEqual(counter.controller, 0, field)
        }
    }

    func testFailureMissingEntitlementOrSignatureHasZeroEffects() throws {
        for identity in [PreflightFixture.identity(entitled: false), PreflightFixture.identity(signed: false)] {
            // Given
            let fixture = PreflightFixture()
            let counter = EffectCounter()
            let context = fixture.context.replacingIdentity(identity)
            // When
            let result = try PreflightFixture.gatedEffects(data: fixture.data(), context: context, counter: counter, now: now)
            // Then
            XCTAssertEqual(result.exitStatus, 2)
            XCTAssertEqual(counter.keychain + counter.controller, 0)
        }
    }

    func testFailureStrictMissingAndUnknownFields() throws {
        let fixture = PreflightFixture()
        for data in [nil, Data("{}".utf8), Data("null".utf8), try fixture.data(changing: "unexpected", to: "$(touch /tmp/never)")] {
            // Given
            let counter = EffectCounter()
            // When
            let result = try PreflightFixture.gatedEffects(data: data, context: fixture.context, counter: counter, now: now)
            // Then
            XCTAssertEqual(result.exitStatus, 2)
            XCTAssertEqual(counter.keychain + counter.controller, 0)
        }
    }

    func testHappyNamespaceIsAttemptSeeded() throws {
        // Given
        let seed = try XCTUnwrap(UUID(uuidString: "3524970b-98b4-4912-b861-a64e9ebf8934"))
        // When
        let first = ProbeNamespace(attempt: "attempt-one", seed: seed)
        // Then
        XCTAssertEqual(first, ProbeNamespace(attempt: "attempt-one", seed: seed))
        XCTAssertNotEqual(first, ProbeNamespace(attempt: "attempt-two", seed: seed))
        XCTAssertTrue(first.service.hasPrefix("com.keyrecord.phase1.probe."))
    }

    func testHappyFakeExerciseCountsEveryGatedOperation() throws {
        // Given
        let fixture = PreflightFixture()
        let counter = EffectCounter()
        // When
        let verdict = try PreflightFixture.gatedEffects(data: fixture.data(), context: fixture.context, counter: counter, now: now)
        // Then
        XCTAssertEqual(verdict, .ready)
        XCTAssertEqual(counter.keychain, 4)
        XCTAssertEqual(counter.controller, 0)
    }

    func testFailureGateRecheckedBeforeEachEffect() throws {
        // Given
        let counter = EffectCounter()
        var checks = 0
        let namespace = ProbeNamespace(attempt: "fixture", seed: UUID())
        // When
        XCTAssertThrowsError(try KeychainLifecycleProbe.exercise(backend: counter, namespace: namespace) {
            checks += 1
            return checks == 1 ? .ready : .blocked(.expired)
        }) { error in
            // Then: expiry between calls blocks the next effect, including cleanup.
            XCTAssertEqual(error as? PreflightBlock, .expired)
        }
        XCTAssertEqual(counter.keychain, 1)
        XCTAssertEqual(counter.controller, 0)
    }

    func testFailureMissingControllerHasZeroEffects() throws {
        // Given
        let fixture = PreflightFixture()
        let counter = EffectCounter()
        let context = PreflightContext(identity: PreflightFixture.identity(), attemptID: fixture.context.attemptID,
                                       scratchRoot: fixture.context.scratchRoot, controllerSHA256: "", controllerExecutable: false)
        // When
        let result = try PreflightFixture.gatedEffects(data: fixture.data(), context: context, counter: counter, now: now)
        // Then
        XCTAssertEqual(result, .blocked(.controller))
        XCTAssertEqual(counter.keychain + counter.controller, 0)
    }
}
