import XCTest
@testable import KeyRecordStore

final class LocalDeletionPlanTests: XCTestCase {
    private let ownedRoot = "/Users/tester/KeyRecord/store"

    func testHappyAllOwnedProceeds() {
        // Given: owned file, an unrecognized file, and a nested directory, all under root
        let entries = [
            DeletionEntry(path: ownedRoot + "/ab/cd.krenc", kind: .ownedFile),
            DeletionEntry(path: ownedRoot + "/stray.bin", kind: .unrecognizedOwnedFile),
            DeletionEntry(path: ownedRoot + "/nested", kind: .directory),
        ]

        // When
        let decision = DeletionPlanner.evaluate(ownedRoot: ownedRoot, entries: entries)

        // Then: proceeds with the original list, unrecognized entry retained in order
        XCTAssertEqual(decision, .proceed(entries))
    }

    func testEmptyRootProceeds() {
        // Given/When: a root scan produced no entries
        let decision = DeletionPlanner.evaluate(ownedRoot: ownedRoot, entries: [])

        // Then
        XCTAssertEqual(decision, .proceed([]))
    }

    func testSymlinkBlocksWithoutOtherChanges() {
        // Given: one owned file and one symlink inside the root
        let symlinkPath = ownedRoot + "/link"
        let entries = [
            DeletionEntry(path: ownedRoot + "/ab.krenc", kind: .ownedFile),
            DeletionEntry(path: symlinkPath, kind: .symlink),
        ]

        // When
        let decision = DeletionPlanner.evaluate(ownedRoot: ownedRoot, entries: entries)

        // Then: blocked solely by the symlink; nothing proceeds
        XCTAssertEqual(decision, .blocked([.symlinkPresent(symlinkPath)]))
    }

    func testForeignEntryBlocks() {
        // Given: one owned file and one foreign-owned entry inside the root
        let foreignPath = ownedRoot + "/foreign.dat"
        let entries = [
            DeletionEntry(path: ownedRoot + "/ab.krenc", kind: .ownedFile),
            DeletionEntry(path: foreignPath, kind: .foreignEntry),
        ]

        // When
        let decision = DeletionPlanner.evaluate(ownedRoot: ownedRoot, entries: entries)

        // Then
        XCTAssertEqual(decision, .blocked([.foreignEntryPresent(foreignPath)]))
    }

    func testPathOutsideRootBlocks() {
        // Given: a `..` escape that would resolve into a sibling store
        let escapingPath = ownedRoot + "/../store2/x.krenc"

        // When
        let escapingDecision = DeletionPlanner.evaluate(
            ownedRoot: ownedRoot,
            entries: [DeletionEntry(path: escapingPath, kind: .ownedFile)])

        // Then
        XCTAssertEqual(escapingDecision, .blocked([.pathOutsideOwnedRoot(escapingPath)]))

        // Given: a sibling directory that shares a mere string prefix with the root
        let siblingPath = "/Users/tester/KeyRecord/store2/x.krenc"

        // When
        let siblingDecision = DeletionPlanner.evaluate(
            ownedRoot: ownedRoot,
            entries: [DeletionEntry(path: siblingPath, kind: .ownedFile)])

        // Then: full-segment prefix matching rejects it
        XCTAssertEqual(siblingDecision, .blocked([.pathOutsideOwnedRoot(siblingPath)]))
    }
}
