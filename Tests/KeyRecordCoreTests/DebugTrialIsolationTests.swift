import XCTest
import KeyRecordCore

final class DebugTrialIsolationTests: XCTestCase {
    private let real = URL(fileURLWithPath: "/Users/example/Library/Application Support/com.keyrecord.app/store")

    func testMissingInputsStayOnProduction() {
        XCTAssertEqual(DebugTrialIsolation.select(store: nil, namespace: nil, realStoreRoot: real), .production)
        XCTAssertEqual(DebugTrialIsolation.select(store: "", namespace: "  ", realStoreRoot: real), .production)
    }

    func testPartialRealNamespaceAndOverlapAreRejected() {
        XCTAssertEqual(DebugTrialIsolation.select(store: "/tmp/trial/store", namespace: nil, realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(store: nil, namespace: "com.keyrecord.trial.round1", realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(store: "/tmp/trial/store", namespace: "com.keyrecord.app", realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(store: "/tmp/trial/store", namespace: "has space", realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(store: "relative/store", namespace: "com.keyrecord.trial.round1", realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(
            store: "/Users/example/Library/Application Support/com.keyrecord.app/store",
            namespace: "com.keyrecord.trial.round1", realStoreRoot: real), .rejected)
        XCTAssertEqual(DebugTrialIsolation.select(
            store: "/Users/example/Library/Application Support/com.keyrecord.app/other",
            namespace: "com.keyrecord.trial.round1", realStoreRoot: real), .rejected)
    }

    func testSymlinkIntoRealStoreIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = root.appendingPathComponent("Application Support/com.keyrecord.app/store")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("alias-store")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(DebugTrialIsolation.select(
            store: link.path, namespace: "com.keyrecord.trial.round1", realStoreRoot: real), .rejected)
    }

    func testExplicitTrialIsSeparate() {
        let selection = DebugTrialIsolation.select(
            store: "/tmp/keyrecord-trial/store", namespace: "com.keyrecord.trial.round1", realStoreRoot: real)
        XCTAssertEqual(selection, .trial(DebugTrialIsolation.Location(
            storeRoot: URL(fileURLWithPath: "/tmp/keyrecord-trial/store"),
            namespace: "com.keyrecord.trial.round1")))
    }
}
