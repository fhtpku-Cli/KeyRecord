import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

final class ModifierRecoveryTests: XCTestCase {
    func testFirstPressAfterReopenRemainsUnknownUntilReleaseThenRecoversLeft() throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let released = ModifierSet(command: .none, option: .none, control: .none,
                                   shift: .none, fn: .none)
        let held = ModifierSet(command: .activeSideUnknown, option: .none, control: .none,
                               shift: .none, fn: .none)

        // A new tap can begin while either Command key is already held. A change
        // for key 55 with Command active cannot distinguish left-down from left-up
        // while right remains held, until a released state has been observed.
        for _ in 0..<2 {
            try deliver(55, .flagsChanged, held, through: queue, expecting: .activeSideUnknown)
            try deliver(0, .keyDown, held, through: queue, expecting: .activeSideUnknown)
            try deliver(0, .keyUp, held, through: queue, expecting: .activeSideUnknown)
            try deliver(55, .flagsChanged, released, through: queue, expecting: .none)
            try deliver(55, .flagsChanged, held, through: queue, expecting: .left)
            try deliver(0, .keyDown, held, through: queue, expecting: .left)

            // Neither foreground recovery nor a new tap may inherit stale sides.
            queue.revoke()
            queue.install(.safe, for: queue.generation)
        }
    }

    private func deliver(_ key: Int, _ kind: KeyEventKind, _ modifiers: ModifierSet,
                         through queue: CaptureQueue, expecting side: ModifierSideState) throws {
        let event = ObservedKeyEvent(keyCode: try KeyCode(key), kind: kind,
            isAutoRepeat: false, modifiers: modifiers, source: .ordinaryObserved,
            generation: queue.generation)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertTrue(queue.deliverOne { observed in
            XCTAssertEqual(observed.modifiers.command, side)
            XCTAssertEqual(observed.keyCode, event.keyCode)
            XCTAssertEqual(observed.kind, kind)
            return .accepted
        })
    }
}
