import XCTest
import KeyRecordCore
import KeyRecordAnalysis
@testable import KeyRecordMappings

final class RecommendationDraftTests: XCTestCase {
    private let bare = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
    private func chord(_ key: Int, _ modifiers: ModifierSet? = nil) throws -> Chord {
        Chord(keyCode: try KeyCode(key), modifiers: modifiers ?? bare)
    }

    func testKarabinerPreservesShortcutSidesAndApplicationScope() throws {
        let output = try chord(8, .init(command: .right, option: .none, control: .left, shift: .none, fn: .none))
        let trigger = try chord(111)
        let request = RecommendationDraft(backend: .karabiner, output: output, trigger: trigger, scope: .application("com.example.Editor"))
        XCTAssertEqual(request.route, .karabiner)
        XCTAssertEqual(request.output, output); XCTAssertEqual(request.trigger, trigger)
        XCTAssertEqual(request.scope, .application("com.example.Editor"))
    }

    func testFirmwareNeverDropsModifiersOrApplicationScope() throws {
        let modifiers: [ModifierSet] = [
            .init(command: .left, option: .none, control: .none, shift: .none, fn: .none),
            .init(command: .none, option: .right, control: .none, shift: .none, fn: .none),
            .init(command: .none, option: .none, control: .both, shift: .none, fn: .none),
            .init(command: .none, option: .none, control: .none, shift: .activeSideUnknown, fn: .none),
            .init(command: .none, option: .none, control: .none, shift: .none, fn: .active),
            .init(command: .none, option: .none, control: .none, shift: .none, fn: .unknown)
        ]
        for backend in [RecommendationBackend.via, .vial] {
            XCTAssertEqual(RecommendationDraft(backend: backend, output: try chord(8), trigger: try chord(0), scope: .global).route, .firmware(output: "KC_C"))
            XCTAssertEqual(RecommendationDraft(backend: backend, output: try chord(8), trigger: try chord(0), scope: .application("com.example.Editor")).route, .unsupported("application"))
            for value in modifiers {
                for pair in [(try chord(8, value), try chord(0)), (try chord(8), try chord(0, value))] {
                    if case .unsupported = RecommendationDraft(backend: backend, output: pair.0, trigger: pair.1, scope: .global).route {} else { XCTFail("Must not degrade modifiers: \(value)") }
                }
            }
        }
    }

    func testInvalidAndStatefulKeysCannotBecomeFirmwareReplacements() throws {
        for backend in [RecommendationBackend.karabiner, .via, .vial] {
            XCTAssertEqual(RecommendationDraft(backend: backend, output: try chord(8), trigger: try chord(8), scope: .global).route, .unsupported("invalid"))
            let stateful = try chord(48, .init(command: .left, option: .none, control: .none, shift: .none, fn: .none))
            XCTAssertEqual(RecommendationDraft(backend: backend, output: stateful, trigger: try chord(0), scope: .global).route, .unsupported("invalid"))
        }
        XCTAssertEqual(VIAReferenceParser.standardKeyCode("KC_ENTER"), VIAReferenceParser.standardKeyCode("KC_ENT"))
        XCTAssertNil(VIAReferenceParser.standardKeyCode("LCTL(KC_C)"))
        XCTAssertNil(VIAReferenceParser.standardKeyCode("LT(1,KC_C)"))
        XCTAssertNil(VIAReferenceParser.standardKeyCode("CUSTOM"))
    }
}
