import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

private actor SuspendedInventoryKeys: ObjectStoreKeySource {
    private var entered: CheckedContinuation<Void, Never>?
    private var resumeInventory: CheckedContinuation<Void, Never>?

    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        await withCheckedContinuation { continuation in
            resumeInventory = continuation
            entered?.resume()
            entered = nil
        }
        return []
    }

    func material(for version: KeyVersion) async throws -> Data { Data(repeating: 7, count: 32) }

    func waitForInventory() async {
        if resumeInventory != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func releaseInventory() {
        resumeInventory?.resume()
        resumeInventory = nil
    }
}

private actor SuspendedMaterialKeys: ObjectStoreKeySource {
    private var installed = false
    private var shouldSuspend = false
    private var entered: CheckedContinuation<Void, Never>?
    private var resumeMaterial: CheckedContinuation<Void, Never>?

    func install() { installed = true }
    func suspendNextMaterial() { shouldSuspend = true }
    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        installed ? [KeyVersion(rawValue: 1)] : []
    }
    func material(for version: KeyVersion) async throws -> Data {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation in
                resumeMaterial = continuation
                entered?.resume()
                entered = nil
            }
        }
        return Data(repeating: 7, count: 32)
    }
    func waitForMaterial() async {
        if resumeMaterial != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func releaseMaterial() {
        resumeMaterial?.resume()
        resumeMaterial = nil
    }
}

final class StoreSessionClosureTests: XCTestCase {
    func testCloseDuringBootstrapDoesNotReopenProtectedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = SuspendedInventoryKeys()
        let store = ObjectStore(root: root, keySource: keys)

        let bootstrap = Task { try await store.bootstrap() }
        await keys.waitForInventory()
        await store.closeProtectedSession()
        await keys.releaseInventory()

        do {
            _ = try await bootstrap.value
            XCTFail("Bootstrap reopened a session after closure")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let state = await store.bootstrapState()
        XCTAssertNil(state)
    }

    func testCloseWhileManifestKeyIsPendingPreventsManifestDecryptionAndPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = SuspendedMaterialKeys()
        let seeded = ObjectStore(root: root, keySource: keys)
        let initialState = try await seeded.bootstrap()
        XCTAssertEqual(initialState, .freshInstall)
        try await seeded.initializeFreshInstallation()
        await keys.install()

        let reopened = ObjectStore(root: root, keySource: keys)
        await keys.suspendNextMaterial()
        let bootstrap = Task { try await reopened.bootstrap() }
        await keys.waitForMaterial()
        await reopened.closeProtectedSession()
        await keys.releaseMaterial()

        do {
            _ = try await bootstrap.value
            XCTFail("Manifest bootstrap completed after protected session closure")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let state = await reopened.bootstrapState()
        XCTAssertNil(state)
    }
}
