import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class DomainSchemaTests: XCTestCase {
    func testStandardKeyCodesRoundTrip() throws {
        // Given / When / Then: supported ANSI, ISO, JIS, modifier and function codes.
        for code in [0, 10, 36, 55, 63, 65, 72, 81, 90, 93, 94, 95, 102, 104, 110, 122, 126] {
            let key = try KeyCode(code)
            XCTAssertEqual(try JSONDecoder().decode(KeyCode.self, from: JSONEncoder().encode(key)), key)
        }
    }

    func testFailureInvalidKeyCodesRejectAtConstructionAndDecoding() throws {
        // Given: holes in Apple's virtual-key table, out-of-range and custom codes.
        for code in [-1, 52, 66, 68, 70, 77, 108, 112, 127, 65535] {
            // When / Then: neither public construction nor decoding bypasses validation.
            XCTAssertThrowsError(try KeyCode(code)) { XCTAssertEqual($0 as? DomainError, .invalidKeyCode(code)) }
            XCTAssertThrowsError(try JSONDecoder().decode(KeyCode.self, from: Data("\(code)".utf8)))
        }
    }

    func testModifierIdentityRetainsUnknownAndSides() throws {
        // Given: startup without recovery; When: construct snapshot; Then: no known-none inference.
        let modifiers = ModifierSet()
        XCTAssertEqual(modifiers.fn, .unknown)
        XCTAssertEqual(modifiers.command, .activeSideUnknown)
        XCTAssertEqual(modifiers.option, .activeSideUnknown)
        XCTAssertEqual(modifiers.control, .activeSideUnknown)
        XCTAssertEqual(modifiers.shift, .activeSideUnknown)
        XCTAssertEqual(Set(ModifierSideState.allCases).count, 5)
        XCTAssertEqual(Set(FnState.allCases).count, 3)
        XCTAssertEqual(try JSONDecoder().decode(ModifierSet.self, from: JSONEncoder().encode(modifiers)), modifiers)
    }

    func testSourceTotalIsDerivedFromSeparatedCounts() throws {
        // Given / When: construct separated counters; Then: total cannot disagree.
        let sources = try DomainFixtures.sources()
        XCTAssertEqual(sources.ordinary.value, 3)
        XCTAssertEqual(sources.suspectedInjection.value, 2)
        XCTAssertEqual(sources.total.value, 5)
        XCTAssertEqual(try JSONDecoder().decode(SourceCounts.self, from: JSONEncoder().encode(sources)), sources)
    }

    func testFailureNegativeCountsReject() throws {
        // Given / When / Then: signed wire values must not become unsigned/wrapped counts.
        XCTAssertThrowsError(try Count(-1)) { XCTAssertEqual($0 as? CountError, .negative(-1)) }
        XCTAssertThrowsError(try JSONDecoder().decode(Count.self, from: Data("-1".utf8)))
        XCTAssertThrowsError(try ActiveDayOrdinal(-1))
    }

    func testFailureSourceOverflowRejectsWithoutWrapping() throws {
        // Given: individually valid counters whose sum overflows.
        let largest = try Count(Int64.max)
        // When / Then: creation and deserialization fail closed.
        XCTAssertThrowsError(try SourceCounts(ordinary: largest, suspectedInjection: Count(1))) {
            XCTAssertEqual($0 as? CountError, .overflow)
        }
        let wire = Data("{\"ordinary\":\(Int64.max),\"suspectedInjection\":1}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SourceCounts.self, from: wire))
        XCTAssertEqual(try SourceCounts(ordinary: largest, suspectedInjection: Count(0)).total, largest)
    }

    func testFailureInjectedSourceTotalRejects() throws {
        // Given: fabricated total; When / Then: strict fields reject it rather than trust it.
        let wire = Data(#"{"ordinary":3,"suspectedInjection":2,"total":99}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SourceCounts.self, from: wire))
    }

    func testSummaryShapeRoundTripsWithoutDailyDetail() throws {
        // Given / When: serialize summary DTO only; Then: exact retained shape.
        let summary = try DomainFixtures.summary()
        let data = try JSONEncoder().encode(summary)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "cycleID", "perChordTotals", "perBareKeyTotals", "distinctActiveDays"])
        XCTAssertEqual(try JSONDecoder().decode(CycleSummary.self, from: data), summary)
    }

    func testFailureUnsupportedSchemasRejectAcrossAllRecords() throws {
        // Given: every persisted record and both stale/future versions.
        let records: [any Encodable] = [
            try DomainFixtures.summary(),
            CycleRecord(cycleID: DomainFixtures.cycleID, index: try Count(0), createdDay: LocalDay("2026-09-12"), closedDay: nil, isCurrent: true),
            DailyBareKeyAggregate(cycleID: DomainFixtures.cycleID, day: LocalDay("2026-09-12"), keyCode: try KeyCode(0), sourceCounts: try DomainFixtures.sources()),
            DailyShortcutAggregate(cycleID: DomainFixtures.cycleID, day: LocalDay("2026-09-12"), identity: ChordBucket(chord: Chord(keyCode: try KeyCode(0), modifiers: ModifierSet()), appBucket: .unknown), classification: .init(kind: .discrete, scope: .normal), sourceCounts: try DomainFixtures.sources()),
            Preferences(currentCycleID: DomainFixtures.cycleID),
        ]
        for record in records {
            let data = try JSONEncoder().encode(record)
            for version in [0, 2, 999] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                object["schemaVersion"] = version
                let tampered = try JSONSerialization.data(withJSONObject: object)
                // When / Then: schema check runs before payload decoding.
                try assertVersionRejection(type(of: record), data: tampered, version: version)
            }
        }
    }

    func testFailureBareKeyAttributionRejectedOnWire() throws {
        // Given: valid bare-key record with an injected attribution field.
        let bare = DailyBareKeyAggregate(cycleID: DomainFixtures.cycleID, day: LocalDay("2026-09-12"), keyCode: try KeyCode(0), sourceCounts: try DomainFixtures.sources())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bare)) as? [String: Any])
        object["appBucket"] = "example.app"
        // When / Then: strict decoding cannot smuggle attribution into a bare-key record.
        XCTAssertThrowsError(try JSONDecoder().decode(DailyBareKeyAggregate.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testGateInputsRetainUnknownWithoutDecisionLogic() {
        // Given / When: initial provider inputs; Then: unknown is distinct from permission.
        let inputs = GateInputs()
        XCTAssertFalse(inputs.collecting)
        XCTAssertEqual(inputs.keyAvailability, .unknown)
        XCTAssertEqual(inputs.sessionLock, .unknown)
        XCTAssertEqual(inputs.secureInput, .unknown)
        XCTAssertEqual(inputs.foreground, .unknown)
        XCTAssertEqual(inputs.exclusion, .unknown)
        XCTAssertNotEqual(ForegroundState.reliablyUnattributable, .unknown)
    }

    private func assertVersionRejection(_ type: any Encodable.Type, data: Data, version: Int) throws {
        let decodable = try XCTUnwrap(type as? any Decodable.Type)
        XCTAssertThrowsError(try JSONDecoder().decode(decodable, from: data)) {
            XCTAssertEqual($0 as? SchemaError, .unsupportedVersion(version))
        }
    }
}
