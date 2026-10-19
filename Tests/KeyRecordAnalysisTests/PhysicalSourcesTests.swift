import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class PhysicalSourcesTests: XCTestCase {
    private let layout = Data(#"{"name":"Reference","vendorProductId":65538,"layers":[["KC_A","KC_C"]]}"#.utf8)
    private let definition = Data(#"{"name":"Reference","vendorId":"0x0001","productId":"0x0002","matrix":{"rows":1,"cols":2},"layouts":{"keymap":[["0,0","0,1"]]}}"#.utf8)
    private let software = Data(#"{"profiles":[{"name":"Chosen","complex_modifications":{"rules":[{"manipulators":[{"type":"basic","from":{"key_code":"a","modifiers":{"mandatory":["left_command"]}},"to":[{"key_code":"c","modifiers":["right_control"]}]}]}]}}]}"#.utf8)
    private func input(_ backend: RecommendationBackend = .via, profile: String = "Chosen") throws -> PhysicalSourceInput {
        try PhysicalSourceInput(backend: backend, scope: .global,
            via: VIAReferenceParser.match(layout: VIAReferenceParser.layout(layout), definition: VIAReferenceParser.definition(definition)),
            software: .init(bytes: software, profile: profile, version: "fixture-version"))
    }
    func testSelectedReferencesConnectGeometryAndSoftwareWithoutQualifyingDeployment() throws {
        let report = try PhysicalSourceReport.references(input())
        XCTAssertEqual(report.evidence.geometry?.positions.count, 2)
        XCTAssertEqual(report.evidence.device, .unknown)
        XCTAssertEqual(report.sources.map(\.status), [.reference, .missing, .reference, .reference, .missing])
        let transform = try XCTUnwrap(report.evidence.chain[1].mapping)
        XCTAssertEqual(transform.mappings, [.init(input: [.hidUsage(0xe3), .hidUsage(0x04)], output: [.hidUsage(0xe4), .hidUsage(0x06)])])
        XCTAssertTrue(transform.completeInverseFor.isEmpty)
        XCTAssertTrue(report.evidence.chain.allSatisfy { $0.status == .absent })
        let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        let result = try PhysicalAnalysis.compare(source: Chord(keyCode: KeyCode(0), modifiers: bare),
            trigger: Chord(keyCode: KeyCode(8), modifiers: bare), scope: .global, evidence: report.evidence)
        XCTAssertEqual(result, .logical(sourceKeys: 1, triggerKeys: 1, reason: .deviceUncertain))
    }
    func testVialNeverInheritsVIAGeometryAndMissingProfileCannotGuess() throws {
        let vial = try PhysicalSourceReport.references(input(.vial))
        XCTAssertNil(vial.evidence.geometry); XCTAssertNil(vial.evidence.chain[0].mapping)
        XCTAssertEqual(vial.sources[0].status, .missing)
        let missing = try PhysicalSourceReport.references(input(profile: "Missing"))
        XCTAssertNil(missing.evidence.chain[1].mapping); XCTAssertEqual(missing.sources[3].status, .unsupported)
        let changed = try PhysicalSourceReport.references(input(), changed: true)
        XCTAssertTrue(changed.sources.allSatisfy { $0.status == .changed })
        XCTAssertTrue(changed.evidence.chain.allSatisfy { $0.status == .externallyChanged })
    }
    func testApplicationRulesCannotBecomeGlobalTransforms() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: software) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        var profile = profiles[0]
        var complex = try XCTUnwrap(profile["complex_modifications"] as? [String: Any])
        var rules = try XCTUnwrap(complex["rules"] as? [[String: Any]])
        var manipulators = try XCTUnwrap(rules[0]["manipulators"] as? [[String: Any]])
        manipulators[0]["conditions"] = [["type":"frontmost_application_if", "bundle_identifiers":["^com\\.example\\.Editor$"]]]
        rules[0]["manipulators"] = manipulators; complex["rules"] = rules; profile["complex_modifications"] = complex
        profiles[0] = profile
        let bytes = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        for scope in [RecommendationScope.global, .application("com.example.Editor"), .application("com.example.Other")] {
            let reference = PhysicalSoftwareReference(bytes: bytes, profile: "Chosen")
            let report = PhysicalSourceReport.references(.init(backend: .karabiner, scope: scope, via: nil, software: reference))
            XCTAssertEqual(report.evidence.chain[1].mapping?.mappings.count, scope == .application("com.example.Editor") ? 1 : 0)
            XCTAssertEqual(report.evidence.scope, scope)
            XCTAssertEqual(report.sources[3].status, .reference)
        }
    }
    func testObservedSourcesStillRequireFullInverseCoverageAndValidChain() throws {
        let references = try PhysicalSourceReport.references(input()).evidence
        let observed = PhysicalEvidence(geometry: references.geometry, chain: references.chain.map {
            .init(link: $0.link, status: .verified, reference: "synthetic", mapping: $0.mapping)
        }, device: .singleVerified, scope: .global)
        let report = PhysicalSourceReport.observed(observed)
        XCTAssertEqual(report.sources.last?.status, .unsupported)
        let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
        if case .logical = PhysicalAnalysis.compare(source: Chord(keyCode: try KeyCode(0), modifiers: bare),
            trigger: Chord(keyCode: try KeyCode(8), modifiers: bare), scope: .global, evidence: report.evidence) {} else { XCTFail("Source presence is not complete physical proof") }
    }
}
