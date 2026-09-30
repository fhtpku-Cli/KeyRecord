import Foundation
import Security
import XCTest
@testable import LifecyclePreflight

final class SignedEffectExecutionTests: XCTestCase {
    func testAllowAddCallsFakeOnceWithRestrictedQuery() throws { try assertAllowed(.add) }
    func testAllowReadCallsFakeOnceWithRestrictedQuery() throws { try assertAllowed(.read) }
    func testAllowAttributesCallsFakeOnceWithRestrictedQuery() throws { try assertAllowed(.attributes) }
    func testAllowDeleteCallsFakeOnceWithRestrictedQuery() throws { try assertAllowed(.delete) }

    func testFailureIdentityRecheckedBeforeNextEffect() throws {
        // Given
        var fixture = try SignedEffectFixture()
        let recorder = CandidateEffectRecorder()
        let executor = SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
        _ = try executor.perform(.add, namespace: fixture.namespace)
        fixture.runningCode = .invalid
        // When
        XCTAssertThrowsError(try executor.perform(.delete, namespace: fixture.namespace)) {
            // Then
            XCTAssertEqual($0 as? PreflightBlock, .unavailableIdentity)
        }
        XCTAssertEqual(recorder.requests.map(\.operation), [.add])
        XCTAssertEqual(executor.calls, 1)
        XCTAssertEqual(executor.denials, 1)
    }

    func testAllowExerciseUsesSameIsolatedNamespaceForAllCRUD() throws {
        // Given
        let fixture = try SignedEffectFixture()
        let recorder = CandidateEffectRecorder()
        let executor = SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
        // When
        let report = try KeychainLifecycleProbe.exercise(backend: executor, namespace: fixture.namespace) { .ready }
        // Then
        XCTAssertEqual(report.keychainCalls, 4)
        XCTAssertEqual(report.controllerCalls, 0)
        XCTAssertEqual(recorder.requests.map(\.operation), [.add, .read, .attributes, .delete])
        XCTAssertEqual(Set(recorder.requests.compactMap { $0.query[kSecAttrService as String] }), [.string(fixture.namespace.service)])
    }

    func testAllowFreshSeedsSeparateQueries() throws {
        // Given
        let first = try SignedEffectFixture()
        let second = try SignedEffectFixture()
        let recorder = CandidateEffectRecorder()
        let executors = [first, second].map { fixture in
            SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
        }
        // When
        for (executor, fixture) in zip(executors, [first, second]) {
            _ = try executor.perform(.add, namespace: fixture.namespace)
        }
        // Then
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertNotEqual(recorder.requests[0].query[kSecAttrService as String], recorder.requests[1].query[kSecAttrService as String])
        XCTAssertNotEqual(recorder.requests[0].query[kSecValueData as String], recorder.requests[1].query[kSecValueData as String])
    }

    private func assertAllowed(_ operation: CandidateOperation) throws {
        // Given
        let fixture = try SignedEffectFixture()
        let recorder = CandidateEffectRecorder()
        let executor = SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
        let intent = SignedEffectIntent(operation: operation, namespace: fixture.namespace)
        // When
        let result = try executor.perform(operation, namespace: fixture.namespace)
        // Then
        XCTAssertEqual(SignedEffectGate.evaluate(intent, evidence: fixture.evidence, expectedNamespace: fixture.expectedNamespace), .allow(intent))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(executor.calls, 1)
        XCTAssertEqual(executor.denials, 0)
        XCTAssertNil(executor.lastDenial)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.operation, operation)
        var expected: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: fixture.namespace.service,
            kSecAttrAccount as String: "when-unlocked",
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        XCTAssertTrue(fixture.namespace.service.hasPrefix(ProbeNamespace.prefix))
        switch operation {
        case .add:
            expected[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard case .data(let bytes) = request.query[kSecValueData as String] else { return XCTFail("Missing add value") }
            XCTAssertEqual(bytes.count, 32)
            expected[kSecValueData as String] = bytes
        case .read:
            expected[kSecReturnData as String] = true
            expected[kSecMatchLimit as String] = kSecMatchLimitOne
        case .attributes:
            expected[kSecReturnAttributes as String] = true
            expected[kSecMatchLimit as String] = kSecMatchLimitOne
        case .delete: break
        }
        XCTAssertEqual(request.foundationQuery as NSDictionary, expected as NSDictionary)
    }

    func testWrongAccessibilityCannotHideAnExactItemFromInspectionOrDeletion() throws {
        let fixture = try SignedEffectFixture()
        let recorder = CandidateEffectRecorder()
        let executor = SignedEffectExecutor(namespace: fixture.expectedNamespace, store: recorder) { fixture.evidence }
        for operation in [CandidateOperation.read, .attributes, .delete] {
            _ = try executor.perform(operation, namespace: fixture.namespace)
        }
        for request in recorder.requests {
            XCTAssertNil(request.query[kSecAttrAccessible as String],
                         "A policy mismatch must remain visible by exact service and account")
            XCTAssertEqual(request.query[kSecAttrService as String], .string(fixture.namespace.service))
            XCTAssertEqual(request.query[kSecAttrAccount as String], .string("when-unlocked"))
        }
    }
}
