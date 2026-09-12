import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

@MainActor
final class KeyringAccessTests: XCTestCase {
    func testMigrationCanUseBothVersionsWithoutReenteringWriter() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        try await f.ring.rotate(to: v2)
        let counts = await f.references.materialCounts
        XCTAssertEqual(counts, [32, 32])
    }

    func testRetainedMigrationAccessIsInvalidAfterSessionEnds() async throws {
        let f = KeyringFixture()
        _ = try await f.ring.bootstrap()
        try await f.ring.rotate(to: v2)
        let retained = await f.references.lastAccess
        let access = try XCTUnwrap(retained)
        await expectKeyringError(.staleGeneration) { try await access.withMaterial(v2) { $0.count } }
    }
}
