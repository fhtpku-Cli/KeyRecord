import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore

private struct UnavailableKeySource: KeyMaterialSource {
    func keyMaterial(for version: KeyVersion) async throws -> Data { throw StoreError.keyUnavailable(version) }
}

final class StoreProviderTests: XCTestCase {
    func testMissingKeyRemainsTypedFailure() async {
        // Given: no accessible key; When: request it; Then: typed failure, no replacement.
        let provider: any KeyMaterialSource = UnavailableKeySource()
        let version = KeyVersion(rawValue: 1)
        do {
            _ = try await provider.keyMaterial(for: version)
            XCTFail("Missing key must fail closed")
        } catch {
            XCTAssertEqual(error as? StoreError, .keyUnavailable(version))
        }
    }
}
