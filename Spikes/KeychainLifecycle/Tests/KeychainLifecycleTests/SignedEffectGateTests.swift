import Foundation
import XCTest
@testable import LifecyclePreflight

final class SignedEffectGateTests: XCTestCase {
    func testFailureHostBundleMismatch() throws {
        try assertDenied(.bundleIDsMismatch) { $0.hostMatches = false }
    }

    func testFailureTestBundleMismatch() throws {
        try assertDenied(.bundleIDsMismatch) { $0.testsMatch = false }
    }

    func testFailureTeamIDMismatch() throws {
        try assertDenied(.teamIDMismatch) {
            $0.runningCode = .valid(RunningSigningIdentity(teamID: "OTHERTEAM",
                certificateSHA256: String(repeating: "a", count: 64), identifier: "com.keyrecord.phase1.probe.host"))
        }
    }

    func testFailureCertificateFingerprintMismatch() throws {
        try assertDenied(.certificateFingerprintMismatch) {
            $0.runningCode = .valid(RunningSigningIdentity(teamID: "FIXTURETEAM",
                certificateSHA256: String(repeating: "b", count: 64), identifier: "com.keyrecord.phase1.probe.host"))
        }
    }

    func testFailureHostIdentifierMismatch() throws {
        try assertDenied(.bundleIDsMismatch) {
            $0.runningCode = .valid(RunningSigningIdentity(teamID: "FIXTURETEAM",
                certificateSHA256: String(repeating: "a", count: 64), identifier: "com.keyrecord.other"))
        }
    }

    func testFailureInvalidRunningCode() throws {
        try assertDenied(.unavailableIdentity) { $0.runningCode = .invalid }
    }

    func testFailureNamespaceMismatch() throws {
        try assertDenied(.namespaceMismatch) { $0.namespace = ProbeNamespace(attempt: "other-attempt", seed: UUID()) }
    }

    func testFailureManifestMissing() throws {
        try assertDenied(.missingManifest) { $0.manifest = .failure(.missingManifest) }
    }

    func testFailureManifestMalformed() throws {
        try assertDenied(.malformedManifest) { $0.manifest = .failure(.malformedManifest) }
    }

    func testFailureOperationNotAuthorizedEvenWhenPreflightReady() throws {
        let data = try PreflightFixture().data(changing: "operations", to: [HostOperation.screen.rawValue])
        let manifest = try JSONDecoder().decode(HostManifest.self, from: data)
        try assertDenied(.operationAllowlistMismatch) { $0.manifest = .success(manifest) }
    }

    func testFailurePreflightMissingManifest() throws { try assertPreflightDenied(.missingManifest) }
    func testFailurePreflightMalformedManifest() throws { try assertPreflightDenied(.malformedManifest) }
    func testFailurePreflightExpired() throws { try assertPreflightDenied(.expired) }
    func testFailurePreflightUnavailableIdentity() throws { try assertPreflightDenied(.unavailableIdentity) }
    func testFailurePreflightHostIDMismatch() throws { try assertPreflightDenied(.hostIDMismatch) }
    func testFailurePreflightArchitectureMismatch() throws { try assertPreflightDenied(.architectureMismatch) }
    func testFailurePreflightMacOSMismatch() throws { try assertPreflightDenied(.macOSMismatch) }
    func testFailurePreflightTeamIDMismatch() throws { try assertPreflightDenied(.teamIDMismatch) }
    func testFailurePreflightCertificateFingerprintMismatch() throws { try assertPreflightDenied(.certificateFingerprintMismatch) }
    func testFailurePreflightBundleIDsMismatch() throws { try assertPreflightDenied(.bundleIDsMismatch) }
    func testFailurePreflightEntitlementsMismatch() throws { try assertPreflightDenied(.entitlementsMismatch) }
    func testFailurePreflightNamespaceMismatch() throws { try assertPreflightDenied(.namespaceMismatch) }
    func testFailurePreflightScratchRootMismatch() throws { try assertPreflightDenied(.scratchRootMismatch) }
    func testFailurePreflightAttemptMismatch() throws { try assertPreflightDenied(.attemptMismatch) }
    func testFailurePreflightOperationAllowlistMismatch() throws { try assertPreflightDenied(.operationAllowlistMismatch) }
    func testFailurePreflightControllerMissing() throws { try assertPreflightDenied(.controllerMissing) }
    func testFailurePreflightControllerNotExecutable() throws { try assertPreflightDenied(.controllerNotExecutable) }
    func testFailurePreflightControllerNotRegular() throws { try assertPreflightDenied(.controllerNotRegular) }
    func testFailurePreflightControllerHashMismatch() throws { try assertPreflightDenied(.controllerHashMismatch) }

    private func assertPreflightDenied(_ reason: PreflightBlock) throws {
        try assertDenied(reason) { $0.preflight = .blocked(reason) }
    }

    private func assertDenied(_ reason: PreflightBlock, changing change: (inout SignedEffectFixture) -> Void) throws {
        // Given
        var fixture = try SignedEffectFixture()
        change(&fixture)
        for operation in CandidateOperation.allCases {
            let recorder = CandidateEffectRecorder()
            let executor = SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
            let intent = SignedEffectIntent(operation: operation, namespace: fixture.namespace)
            // When
            let decision = SignedEffectGate.evaluate(intent, evidence: fixture.evidence, expectedNamespace: fixture.expectedNamespace)
            // Then
            XCTAssertEqual(decision, .deny(reason), "\(operation): \(reason)")
            XCTAssertThrowsError(try executor.perform(operation, namespace: fixture.namespace)) {
                XCTAssertEqual($0 as? PreflightBlock, reason, "\(operation)")
            }
            XCTAssertEqual(recorder.requests.count, 0, "\(operation): \(reason)")
            XCTAssertEqual(executor.calls, 0)
            XCTAssertEqual(executor.denials, 1)
            XCTAssertEqual(executor.lastDenial, reason)
        }
    }
}
