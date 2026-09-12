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

    func testExpired() throws {
        try assertBlocked(.expired, data: PreflightFixture().data(changing: "expiresAt", to: "2000-01-01T00:00:00Z"))
    }

    func testExpiredWhenDateMalformed() throws {
        try assertBlocked(.expired, data: PreflightFixture().data(changing: "expiresAt", to: "not-a-date"))
    }

    func testHostIDMismatch() throws {
        try assertBlocked(.hostIDMismatch, data: PreflightFixture().data(changing: "hostID", to: "other-host"))
    }

    func testArchitectureMismatch() throws {
        try assertBlocked(.architectureMismatch, data: PreflightFixture().data(changing: "architecture", to: "x86_64"))
    }

    func testMacOSMismatch() throws {
        try assertBlocked(.macOSMismatch, data: PreflightFixture().data(changing: "macOS", to: "0.0"))
    }

    func testTeamIDMismatch() throws {
        try assertBlocked(.teamIDMismatch, data: PreflightFixture().data(changing: "teamID", to: "OTHERTEAM"))
    }

    func testCertificateFingerprintMismatch() throws {
        try assertBlocked(.certificateFingerprintMismatch,
                          data: PreflightFixture().data(changing: "certificateSHA256", to: String(repeating: "c", count: 64)))
    }

    func testBundleIDsMismatch() throws {
        try assertBlocked(.bundleIDsMismatch, data: PreflightFixture().data(changing: "bundleIDs", to: ["com.keyrecord.other"]))
    }

    func testEntitlementsMismatch() throws {
        let fixture = PreflightFixture()
        try assertBlocked(.entitlementsMismatch, data: fixture.data(),
                          context: fixture.context.replacingIdentity(PreflightFixture.identity(entitled: false)))
    }

    func testNamespaceMismatch() throws {
        try assertBlocked(.namespaceMismatch, data: PreflightFixture().data(changing: "namespacePrefix", to: "com.keyrecord.app"))
    }

    func testScratchRootMismatch() throws {
        try assertBlocked(.scratchRootMismatch, data: PreflightFixture().data(changing: "scratchRoot", to: "/fixture/attempt-one/../escape"))
    }

    func testAttemptMismatch() throws {
        try assertBlocked(.attemptMismatch, data: PreflightFixture().data(changing: "attemptID", to: "replayed"))
    }

    func testOperationAllowlistMismatch() throws {
        try assertBlocked(.operationAllowlistMismatch,
                          data: PreflightFixture().data(changing: "operations", to: HostOperation.allCases.dropLast().map(\.rawValue)))
    }

    func testOperationAllowlistMismatchWhenDuplicated() throws {
        try assertBlocked(.operationAllowlistMismatch,
                          data: PreflightFixture().data(changing: "operations", to: (HostOperation.allCases + [.keychain]).map(\.rawValue)))
    }

    func testControllerMissing() throws {
        let fixture = PreflightFixture()
        try assertBlocked(.controllerMissing, data: fixture.data(),
                          context: fixture.context(controllerExists: false, executable: false, regular: false))
    }

    func testControllerNotExecutable() throws {
        let fixture = PreflightFixture()
        try assertBlocked(.controllerNotExecutable, data: fixture.data(),
                          context: fixture.context(controllerExists: true, executable: false, regular: true))
    }

    func testControllerNotRegular() throws {
        let fixture = PreflightFixture()
        try assertBlocked(.controllerNotRegular, data: fixture.data(),
                          context: fixture.context(controllerExists: true, executable: true, regular: false))
    }

    func testControllerHashMismatch() throws {
        try assertBlocked(.controllerHashMismatch,
                          data: PreflightFixture().data(changing: "controllerSHA256", to: String(repeating: "b", count: 64)))
    }

    func testUnavailableIdentity() throws {
        let fixture = PreflightFixture()
        try assertBlocked(.unavailableIdentity, data: fixture.data(),
                          context: fixture.context.replacingIdentity(PreflightFixture.identity(signed: false)))
    }

    func testMissingManifest() throws {
        try assertBlocked(.missingManifest, data: nil)
    }

    func testMalformedManifest() throws {
        try assertBlocked(.malformedManifest, data: Data("{}".utf8))
    }

    func testMalformedManifestWhenNull() throws {
        try assertBlocked(.malformedManifest, data: Data("null".utf8))
    }

    func testMalformedManifestWhenUnknownField() throws {
        try assertBlocked(.malformedManifest, data: PreflightFixture().data(changing: "unexpected", to: "$(touch /tmp/never)"))
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

    private func assertBlocked(_ reason: PreflightBlock, data: Data?, context: PreflightContext = PreflightFixture().context) throws {
        // Given: a fake backend that counts every attempted effect.
        let counter = EffectCounter()
        // When: the pure gate evaluates the supplied snapshot.
        let verdict = Preflight.evaluate(data: data, context: context, now: now)
        // Then: the exact rejection is preserved by the effect gate, with no backend calls.
        XCTAssertEqual(verdict, .blocked(reason), reason.rawValue)
        XCTAssertEqual(verdict.exitStatus, 2, reason.rawValue)
        let gated = try PreflightFixture.gatedEffects(data: data, context: context, counter: counter, now: now)
        XCTAssertEqual(gated, .blocked(reason), reason.rawValue)
        XCTAssertEqual(counter.keychain, 0, reason.rawValue)
        XCTAssertEqual(counter.controller, 0, reason.rawValue)
    }
}
