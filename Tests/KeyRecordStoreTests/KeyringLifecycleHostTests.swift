import Foundation
import XCTest
@testable import KeyRecordStore

@MainActor
final class KeyringLifecycleHostTests: XCTestCase {
    func testLiveLifecycleIsExplicitlyBlockedNotQualifiedByFakeSuccess() async throws {
        let namespace = try KeychainNamespace("com.keyrecord.tests.keyring.hosted")
        let backend = BlockedLiveKeychain()
        await expectKeyringError(.liveQualificationBlocked) { try await backend.versions(in: namespace) }
        await expectKeyringError(.liveQualificationBlocked) { try await backend.read(.key(namespace, v1)) }
        let item = KeychainItem(id: .key(namespace, v1), material: Data(repeating: 0, count: 32),
                               policy: .candidateWhenUnlockedThisDeviceOnly)
        await expectKeyringError(.liveQualificationBlocked) { try await backend.add(item) }
        await expectKeyringError(.liveQualificationBlocked) { try await backend.delete(item.id) }
        let metadata = KeyringMetadata(current: v1, versions: [v1])
        let update = KeychainMetadataUpdate(id: .metadata(namespace), expected: nil,
            replacement: try metadata.encoded(), policy: .candidateWhenUnlockedThisDeviceOnly)
        await expectKeyringError(.liveQualificationBlocked) { try await backend.publish(update) }
        // This assertion tests the BLOCKED boundary, not the hosted lifecycle. Q11 excludes this suite.
        print("outcome=BLOCKED suite=KeyringLifecycleHostTests code=task7QualificationMissing keychainCalls=0 signingCalls=0 liveLifecycleExecuted=false")
    }
}
