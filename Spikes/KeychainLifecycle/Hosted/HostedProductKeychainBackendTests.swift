#if DEBUG
import Foundation
import Security
import XCTest
import KeyRecordCore
import LifecyclePreflight
@testable import KeyRecordStore

private enum ProductKeychainTrialFailure: Error {
    case readbackMismatch, inventoryMismatch, attributesMismatch, deletionIncomplete
}

private final class MutableProductEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SignedEffectEvidence
    init(_ value: SignedEffectEvidence) { self.value = value }
    func get() -> SignedEffectEvidence { lock.withLock { value } }
    func set(_ value: SignedEffectEvidence) { lock.withLock { self.value = value } }
}

@MainActor
final class HostedProductKeychainBackendTests: XCTestCase {
    func testAuthorizationIsRevalidatedBetweenProductOperations() throws {
        let fixture = try SignedEffectFixture()
        let evidence = MutableProductEvidence(fixture.evidence)
        let memory = MemoryLocalKeychainClient()
        let client = AuthorizedProductKeychainClient(namespace: fixture.namespace, accounts: ["metadata"],
            client: memory, evidence: { evidence.get() })
        let query = LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "metadata")
        _ = try client.copyMatching(query)
        evidence.set(SignedEffectEvidence(identity: fixture.evidence.identity,
            manifest: fixture.evidence.manifest, preflight: .blocked(.expired)))
        XCTAssertThrowsError(try client.delete(query)) { XCTAssertEqual($0 as? PreflightBlock, .expired) }
        XCTAssertEqual(memory.queries.count, 1)
    }

    func testAuthorizationDenialStopsEveryProductClientOperationBeforeDispatch() throws {
        let fixture = try SignedEffectFixture()
        let denied = SignedEffectEvidence(identity: fixture.evidence.identity,
            manifest: fixture.evidence.manifest, preflight: .blocked(.expired))
        let memory = MemoryLocalKeychainClient()
        let client = AuthorizedProductKeychainClient(namespace: fixture.namespace, accounts: ["metadata"],
                                                    client: memory, evidence: { denied })
        let query = LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "metadata")
        let attributes = LocalKeychainQueries.attributesForUpdate(data: Data([1]),
            accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly)
        XCTAssertThrowsError(try client.copyMatching(query)) { XCTAssertEqual($0 as? PreflightBlock, .expired) }
        XCTAssertThrowsError(try client.add(query)) { XCTAssertEqual($0 as? PreflightBlock, .expired) }
        XCTAssertThrowsError(try client.update(query, attributes: attributes)) { XCTAssertEqual($0 as? PreflightBlock, .expired) }
        XCTAssertThrowsError(try client.delete(query)) { XCTAssertEqual($0 as? PreflightBlock, .expired) }
        XCTAssertTrue(memory.queries.isEmpty)
    }

    func testProductClientRejectsForeignIdentityAndInteractiveFallback() throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = AuthorizedProductKeychainClient(namespace: fixture.namespace, accounts: ["metadata"],
                                                    client: memory, evidence: { evidence })
        let allowed = LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "metadata")
        var interactive = allowed
        interactive[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIAllow
        for query in [interactive,
            LocalKeychainQueries.productIdentity(service: "com.keyrecord.app", account: "metadata"),
            LocalKeychainQueries.productIdentity(service: fixture.namespace.service, account: "master-v99")] {
            XCTAssertThrowsError(try client.delete(query)) { XCTAssertEqual($0 as? PreflightBlock, .namespaceMismatch) }
        }
        var changedIdentity = LocalKeychainQueries.attributesForUpdate(data: Data([1]),
            accessible: LocalKeychainQueries.accessibleWhenUnlockedThisDeviceOnly)
        changedIdentity[kSecAttrService as String] = "com.keyrecord.app"
        XCTAssertThrowsError(try client.update(allowed, attributes: changedIdentity)) {
            XCTAssertEqual($0 as? PreflightBlock, .namespaceMismatch)
        }
        let weakerPolicy = LocalKeychainQueries.attributesForAdd(identity: allowed, data: Data([1]),
            accessible: kSecAttrAccessibleAfterFirstUnlock)
        XCTAssertThrowsError(try client.add(weakerPolicy)) {
            XCTAssertEqual($0 as? PreflightBlock, .namespaceMismatch)
        }
        XCTAssertTrue(memory.queries.isEmpty)
    }

    func testAuthorizedProductBackendUsesGuardedClient() async throws {
        let fixture = try SignedEffectFixture()
        let evidence = fixture.evidence
        let memory = MemoryLocalKeychainClient()
        let client = AuthorizedProductKeychainClient(namespace: fixture.namespace, accounts: ["master-v1"],
                                                    client: memory, evidence: { evidence })
        let backend = LocalKeychainBackend(client: client)
        let namespace = try KeychainNamespace(fixture.namespace.service)
        let id = KeychainItemID.key(namespace, KeyVersion(rawValue: 1))
        let material = Data(repeating: 0x42, count: 32)
        try await backend.add(.init(id: id, material: material, policy: .candidateWhenUnlockedThisDeviceOnly))
        let restored = try await backend.read(id)
        XCTAssertTrue(restored == material)
        try await backend.delete(id)
        XCTAssertEqual(memory.queries.count, 3)
    }

    func testAuthorizedIsolatedProductKeychainLifecycle() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KEYRECORD_HOSTED_PRODUCT_KEYCHAIN_TRIAL"] == "1" else {
            throw XCTSkip("No authorized product Keychain trial requested")
        }
        let path = try XCTUnwrap(environment["PHASE1_QA_ATTEMPT"])
        guard path.hasPrefix("/") else { throw PreflightBlock.scratchRootMismatch }
        let attempt = URL(fileURLWithPath: path).standardizedFileURL
        let evidence = SignedCandidateBackend.evidence(attempt: attempt)
        let namespace = ProbeNamespace(attempt: attempt.lastPathComponent, seed: UUID())
        guard case .ready = SignedEffectGate.authorizeKeychain(namespace: namespace, evidence: evidence,
                                                              expectedNamespace: namespace),
              case .success(let manifest) = evidence.manifest, manifest.operations == [.keychain] else {
            throw PreflightBlock.operationAllowlistMismatch
        }
        let record = attempt.appendingPathComponent("product-keychain-service.txt")
        guard !FileManager.default.fileExists(atPath: record.path),
              FileManager.default.createFile(atPath: record.path, contents: Data(namespace.service.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let productNamespace = try KeychainNamespace(namespace.service)
        let first = KeyVersion(rawValue: 1), second = KeyVersion(rawValue: 2)
        let ids: [KeychainItemID] = [.key(productNamespace, first), .key(productNamespace, second), .metadata(productNamespace)]
        let client = AuthorizedProductKeychainClient(attempt: attempt, namespace: namespace,
            accounts: Set(ids.map(\.account) + ["master-v3"]))
        let backend = LocalKeychainBackend(client: client)
        var owned: [KeychainItemID] = []
        var failure: (any Error)?
        do {
            for id in ids {
                guard try await backend.read(id) == nil else { throw KeyringError.duplicateItem }
            }
            var material = Data(count: 32)
            let entropy = material.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            guard entropy == errSecSuccess else { throw KeyringError.entropyDenied }
            for id in ids.prefix(2) {
                try await backend.add(.init(id: id, material: material, policy: .candidateWhenUnlockedThisDeviceOnly))
                owned.append(id)
                let restored = try await backend.read(id)
                guard restored == material else { throw ProductKeychainTrialFailure.readbackMismatch }
            }
            let before = try KeyringMetadata(current: first, versions: [first]).encoded()
            let after = try KeyringMetadata(current: second, versions: [first, second],
                                            rotation: KeyRotation(from: first, to: second)).encoded()
            try await backend.publish(.init(id: ids[2], expected: nil, replacement: before,
                                            policy: .candidateWhenUnlockedThisDeviceOnly))
            owned.append(ids[2])
            try await backend.publish(.init(id: ids[2], expected: before, replacement: after,
                                            policy: .candidateWhenUnlockedThisDeviceOnly))
            let inventory = try await backend.versions(in: productNamespace)
            guard inventory == [first, second] else { throw ProductKeychainTrialFailure.inventoryMismatch }
            let reopened = LocalKeychainBackend(client: client)
            let metadata = try await reopened.read(ids[2])
            guard metadata == after else { throw ProductKeychainTrialFailure.readbackMismatch }
            for id in ids {
                let identity = LocalKeychainQueries.productIdentity(service: namespace.service, account: id.account)
                let result = try client.copyMatching(LocalKeychainQueries.queryForReadingAttributes(identity: identity))
                let attributes = result.value as? [String: Any]
                guard result.status == errSecSuccess,
                      attributes?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                      attributes?[kSecAttrSynchronizable as String] as? Bool == false
                else { throw ProductKeychainTrialFailure.attributesMismatch }
            }
            try await backend.delete(ids[1])
            let missing = try await reopened.read(ids[1])
            guard missing == nil else { throw ProductKeychainTrialFailure.deletionIncomplete }
        } catch { failure = error }
        for id in owned.reversed() {
            do {
                try await backend.delete(id)
                let remaining = try await backend.read(id)
                guard remaining == nil else { throw ProductKeychainTrialFailure.deletionIncomplete }
            } catch {
                XCTFail("Product test-item cleanup blocked; retained service record requires follow-up")
                if failure == nil { failure = error }
            }
        }
        if let failure { throw failure }
    }
}
#endif
