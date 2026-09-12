import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

actor FakeObjectKeySource: ObjectStoreKeySource {
    var materials: [UInt32: Data]
    var removed: Set<UInt32> = []
    var failVersion: UInt32?

    init(versions: [UInt32] = [1]) {
        materials = Dictionary(uniqueKeysWithValues: versions.map { ($0, Data(repeating: UInt8($0 + 6), count: 32)) })
    }

    func seed(version: UInt32) { materials[version] = Data(repeating: UInt8(version + 6), count: 32) }
    func remove(version: UInt32) { materials[version] = nil; removed.insert(version) }
    func failMaterial(version: UInt32) { failVersion = version }

    func namespaceKeyVersions() async throws -> Set<KeyVersion> {
        Set(materials.keys.map { KeyVersion(rawValue: $0) })
    }

    func material(for version: KeyVersion) async throws -> Data {
        guard let material = materials[version.rawValue] else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        guard failVersion != version.rawValue else {
            throw ObjectStoreError.corruption(.envelopeKeyMissing)
        }
        return material
    }
}

struct StoreHarness {
    let directory: URL
    let keySource: FakeObjectKeySource

    init(versions: [UInt32] = []) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrecord-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        keySource = FakeObjectKeySource(versions: versions)
    }

    var root: URL { directory.appendingPathComponent("store", isDirectory: true) }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore() -> ObjectStore {
        ObjectStore(root: root, keySource: keySource)
    }

    @discardableResult
    func bootFresh(version: UInt32 = 1, store: ObjectStore? = nil) async throws -> ObjectStore {
        let store = store ?? makeStore()
        let state = try await store.bootstrap()
        XCTAssertEqual(state, .freshInstall)
        await keySource.seed(version: version)
        try await store.initializeFreshInstallation(version: KeyVersion(rawValue: version))
        return store
    }

    func rootEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }
}

func objectIdentity(_ logicalID: String, schemaVersion: UInt32 = 1) throws -> CanonicalLogicalIdentity {
    try CanonicalLogicalIdentity(objectType: "com.keyrecord.preferences",
                                 schemaVersion: schemaVersion, logicalIDText: logicalID)
}

func objectIdentity(type: String, _ logicalID: String, schemaVersion: UInt32 = 1) throws
    -> CanonicalLogicalIdentity {
    try CanonicalLogicalIdentity(objectType: type, schemaVersion: schemaVersion,
                                 logicalIDText: logicalID)
}

func withHarness(versions: [UInt32] = [], _ body: (StoreHarness) async throws -> Void) async throws {
    let harness = try StoreHarness(versions: versions)
    do {
        try await body(harness)
        harness.cleanup()
    } catch {
        harness.cleanup()
        throw error
    }
}

func expectStoreError<T>(
    _ expected: ObjectStoreError,
    file: StaticString = #filePath, line: UInt = #line,
    operation: () async throws -> T
) async {
    do { _ = try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
    catch let error as ObjectStoreError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected ObjectStoreError \(expected), got \(error)", file: file, line: line)
    }
}

func writeBytes(_ bytes: Data, name: String, in directory: URL) throws {
    try bytes.write(to: directory.appendingPathComponent(name))
}
