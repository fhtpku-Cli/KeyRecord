import Foundation
import XCTest
import KeyRecordCore
import KeyRecordStore

@MainActor
final class PrivacyBoundaryTests: XCTestCase {
    private let canary = "com.example.T20_CANARY_7F92"

    func testCanaryWhenNormalizedAndSealedLeavesNoPlaintextInOwnedRoot() async throws {
        // Given: fixed, synthetic key pattern; no event text is accepted by ObservedKeyEvent.
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .reliablyUnattributable, exclusion: .included))
        fixture.aggregate.update(normalizer.gate)
        for code in [0, 17, 20, 0, 17, 20] {
            for command in [ModifierSideState.none, .left] {
                for kind in [KeyEventKind.keyDown, .keyUp] {
                    let event = ObservedKeyEvent(keyCode: try KeyCode(code), kind: kind,
                        isAutoRepeat: false, modifiers: ModifierSet(command: command, option: .none,
                            control: .none, shift: .none, fn: .none), source: .ordinaryObserved,
                        generation: normalizer.gate.generation)
                    try fixture.aggregate.process(normalizer.process(event),
                        generation: normalizer.gate.generation, clock: IntegrationClock())
                }
            }
        }
        // Feed a canary foreground through the same normalizer, but only bare keys can count here.
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: canary), exclusion: .included))
        fixture.aggregate.update(normalizer.gate)
        let bare = ObservedKeyEvent(keyCode: try KeyCode(42), kind: .keyDown,
            isAutoRepeat: false, modifiers: ModifierSet(command: .none, option: .none,
                control: .none, shift: .none, fn: .none), source: .ordinaryObserved,
            generation: normalizer.gate.generation)
        try fixture.aggregate.process(normalizer.process(bare),
            generation: normalizer.gate.generation, clock: IntegrationClock())
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        XCTAssertEqual(objects.count, 2)
        // When: real serializer, AEAD envelope, opaque locator and atomic filesystem writer.
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(objects, generation: fixture.gate.begin())
        // Then: inspect every file, including metadata and manifest, without extension filtering.
        let forbidden = [canary, "com.apple.TextEdit", "sourceCounts", "appBucket",
            "keyCode", "command", "integration-cycle", "eventTimestamp", "events"]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: fixture.root,
            includingPropertiesForKeys: [.isRegularFileKey]))
        var files = 0
        var bytes = 0
        for case let file as URL in enumerator.allObjects {
            for token in forbidden { XCTAssertFalse(file.path.contains(token)) }
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let data = try Data(contentsOf: file)
            files += 1
            bytes += data.count
            for token in forbidden { XCTAssertNil(data.range(of: Data(token.utf8)), file.lastPathComponent) }
        }
        XCTAssertGreaterThanOrEqual(files, 3)
        let entries = try await fixture.store.entries()
        XCTAssertEqual(entries.count, objects.count)
        for entry in entries {
            let data = try await fixture.store.readProtected(entry.identity, gate: fixture.gate)
            XCTAssertNil(data.range(of: Data(canary.utf8)))
            let component = try entry.identity.shardComponents()
            switch component.aggregateType {
            case "shortcut":
                let rows = try JSONDecoder().decode([DailyShortcutAggregate].self, from: data)
                XCTAssertEqual(rows.count, 3)
                XCTAssertTrue(rows.allSatisfy { $0.identity.appBucket == .unknown })
                try PrivacySchemaAudit.checkJSON(data, allowed: PrivacySchemaAudit.shortcutKeys)
            case "bareKey":
                let rows = try JSONDecoder().decode([DailyBareKeyAggregate].self, from: data)
                XCTAssertEqual(rows.count, 4)
                try PrivacySchemaAudit.checkJSON(data, allowed: PrivacySchemaAudit.bareKeys)
            default: XCTFail("Unexpected persisted object")
            }
        }
        print("T20_CANARY files=\(files) bytes=\(bytes) decryptedObjects=\(entries.count) plaintextMatches=0 synthetic=true")
    }

    func testExcludedForegroundWhenOfferedToStoreProducesNoObjects() async throws {
        // Given
        let fixture = IntegrationFixture()
        defer { fixture.cleanup() }
        try await fixture.boot()
        var normalizer = ChordNormalizer()
        normalizer.update(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: "com.apple.TextEdit"), exclusion: .excluded))
        fixture.aggregate.update(normalizer.gate)
        // When
        let event = ObservedKeyEvent(keyCode: try KeyCode(17), kind: .keyDown,
            isAutoRepeat: false, modifiers: ModifierSet(command: .left, option: .none,
                control: .none, shift: .none, fn: .none), source: .ordinaryObserved,
            generation: normalizer.gate.generation)
        try fixture.aggregate.process(normalizer.process(event),
            generation: normalizer.gate.generation, clock: IntegrationClock())
        let objects = try AggregatePersistence.objects(fixture.aggregate)
        try await FencedObjectWriter(store: fixture.store, gate: fixture.gate)
            .write(objects, generation: fixture.gate.begin())
        // Then: excluded is closed, not UNKNOWN; only reliably unattributable can count UNKNOWN.
        XCTAssertTrue(objects.isEmpty)
        let entries = try await fixture.store.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testLeakFixtureWhenInjectedIntoPayloadIsRejected() throws {
        // Given
        let data = Data(#"[{"sourceCounts":{},"eventTimestamps":[1,2],"events":[17,20]}]"#.utf8)
        // When / Then
        XCTAssertThrowsError(try PrivacySchemaAudit.checkJSON(data, allowed: PrivacySchemaAudit.shortcutKeys))
    }

    func testBareAppFixtureWhenDecodedIsRejected() throws {
        // Given
        let fixture = DailyBareKeyAggregate(cycleID: CycleID(rawValue: "synthetic"),
            day: LocalDay("2026-09-14"), keyCode: try KeyCode(17),
            sourceCounts: try SourceCounts(ordinary: Count(1), suspectedInjection: Count(0)))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as? [String: Any])
        fields["bundleID"] = canary
        let data = try JSONSerialization.data(withJSONObject: fields)
        // When / Then: product decoder, not a fixture-only acceptance predicate.
        XCTAssertThrowsError(try JSONDecoder().decode(DailyBareKeyAggregate.self, from: data))
        XCTAssertThrowsError(try PrivacySchemaAudit.checkJSON(data, allowed: PrivacySchemaAudit.bareKeys))
    }
}
