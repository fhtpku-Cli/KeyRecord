import XCTest
import KeyRecordCore
@testable import KeyRecordAnalysis

final class KarabinerReferenceParserTests: XCTestCase {
    func testNumericDisabledFlagCannotHideUnresolvedRule() throws {
        let data = Data(#"{"profiles":[{"name":"Synthetic","complex_modifications":{"rules":[{"enabled":0,"manipulators":[{"type":"future"}]}]}}]}"#.utf8)
        let reference = try KarabinerReferenceParser.parse(data)
        XCTAssertEqual(reference.profiles[0].evidence.unsupportedRuleCount, 1)
    }

    private func parse(_ rule: String, selected: String = "true") throws -> KarabinerReference {
        try KarabinerReferenceParser.parse(Data("""
        {"profiles":[{"name":"Synthetic", "selected":\(selected),"complex_modifications":{"rules":[{"manipulators":[\(rule)]}]}}]}
        """.utf8))
    }

    func testStandardRuleAndLiteralApplicationBecomeReferenceOnlyEvidence() throws {
        let rule = #"{"type":"basic","from":{"key_code":"f1","modifiers":{"mandatory":["left_command"]}},"to":[{"key_code":"c","modifiers":["left_command","left_shift"]}],"conditions":[{"type":"frontmost_application_if","bundle_identifiers":["^com\\.example\\.Editor$"]}]}"#
        let reference = try parse(rule)
        XCTAssertEqual(reference.selectedProfile, "0")
        let evidence = try XCTUnwrap(reference.profiles.first?.evidence)
        XCTAssertEqual(evidence.origin, .selectedCopy)
        XCTAssertEqual(evidence.rules.first?.scope, .application("com.example.Editor"))
        XCTAssertEqual(evidence.unsupportedRuleCount, 0)
        XCTAssertEqual(evidence.rules.first?.output?.keyCode.value, 8)
    }

    func testDynamicUnknownAndUnboundedConditionRulesStayUnresolved() throws {
        let rules = [
            #"{"type":"basic","from":{"key_code":"f1"},"to":[{"shell_command":"synthetic command not executed"}]}"#,
            #"{"type":"basic","from":{"key_code":"f1"},"to":[{"key_code":"c"}],"to_if_alone":[{"key_code":"f2"}]}"#,
            #"{"type":"basic","from":{"key_code":"future_key"},"to":[{"key_code":"c"}]}"#,
            #"{"type":"basic","from":{"key_code":"f1"},"to":[{"key_code":"c"}],"conditions":[{"type":"frontmost_application_if","bundle_identifiers":[".*"]}]}"#]
        for rule in rules {
            let evidence = try parse(rule).profiles[0].evidence
            XCTAssertTrue(evidence.rules.isEmpty)
            XCTAssertEqual(evidence.unsupportedRuleCount, 1)
        }
    }

    func testSimpleMappingsDetectOverlapWithoutClaimingCompleteTransforms() throws {
        let reference = try KarabinerReferenceParser.parse(Data(#"{"profiles":[{"name":"Synthetic","simple_modifications":[{"from":{"key_code":"f1"},"to":[{"key_code":"f2"}]}]}]}"#.utf8))
        let evidence = reference.profiles[0].evidence
        XCTAssertEqual(evidence.rules.first?.anyModifiers, true)
        XCTAssertEqual(evidence.unsupportedRuleCount, 1)
        XCTAssertNil(evidence.rules.first?.output)
    }

    func testAmbiguousProfileSelectionAndProtectedJSONAreNotGuessed() throws {
        let reference = try KarabinerReferenceParser.parse(Data(#"{"profiles":[{"name":"A","selected":true},{"name":"B","selected":true}]}"#.utf8))
        XCTAssertNil(reference.selectedProfile)
        for document in [#"{"profiles":[],"profiles":[]}"#, #"{"profiles":[]}"#, #"{"profiles":[{}]}"#] {
            XCTAssertThrowsError(try KarabinerReferenceParser.parse(Data(document.utf8)))
        }
    }
}
