import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

extension CaptureQueueTests {
    func testProductMarkedNeverPublishesOrMutatesHeldState() throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let event = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged,
            isAutoRepeat: false, modifiers: ModifierSet(command: .left), source: .productMarked,
            generation: queue.generation)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertTrue(queue.deliverOne { _ in XCTFail("product marker"); return .accepted })
        XCTAssertEqual(queue.modifiers, ModifierSet())
    }

    func testReducerReconstructsSidesAndResetsAcrossTapLoss() throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let baseline = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyUp,
            isAutoRepeat: false, modifiers: ModifierSet(command: .none, option: .none,
                control: .none, shift: .none, fn: .none), source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(baseline), .accepted)
        XCTAssertTrue(queue.deliverOne { _ in .accepted })
        let flags = ModifierSet(command: .activeSideUnknown, option: .none, control: .none, shift: .none, fn: .none)
        let event = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged,
            isAutoRepeat: false, modifiers: flags, source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertTrue(queue.deliverOne { event in
            XCTAssertEqual(event.modifiers.command, .left)
            return .accepted
        })
        queue.revoke()
        XCTAssertEqual(queue.modifiers, ModifierSet())
        queue.install(.safe, for: queue.generation)
        let terminal = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown,
            isAutoRepeat: false, modifiers: flags, source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(terminal), .accepted)
        XCTAssertTrue(queue.deliverOne { event in
            XCTAssertEqual(event.modifiers.command, .activeSideUnknown)
            return .accepted
        })
    }

    func testSerialDeliveryIsFIFOAcrossRingWrap() throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let count = CaptureLock(0)
        for _ in 0..<2 {
            for index in 0..<4096 {
                let event = ObservedKeyEvent(keyCode: try KeyCode(index % 2), kind: .keyDown,
                    isAutoRepeat: false, modifiers: ModifierSet(), source: .ordinaryObserved,
                    generation: queue.generation)
                XCTAssertEqual(queue.handoff(event), .accepted)
            }
            for _ in 0..<4096 {
                XCTAssertTrue(queue.deliverOne { event in
                    count.withLock { index in
                        XCTAssertEqual(event.keyCode.value, index % 2)
                        index += 1
                    }
                    return .accepted
                })
            }
        }
        XCTAssertEqual(count.withLock { $0 }, 8192)
        XCTAssertFalse(queue.deliverOne { _ in XCTFail("empty"); return .accepted })
    }

    func testRejectedSinkRevokesAndPreventsLaterPublication() throws {
        for rejection in [EventHandoffResult.closed, .overflow] {
            let queue = CaptureQueue()
            queue.install(.safe, for: queue.generation)
            let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown,
                isAutoRepeat: false, modifiers: ModifierSet(), source: .ordinaryObserved,
                generation: queue.generation)
            XCTAssertEqual(queue.handoff(event), .accepted)
            XCTAssertEqual(queue.handoff(event), .accepted)
            XCTAssertTrue(queue.deliverOne { _ in rejection })
            XCTAssertFalse(queue.deliverOne { _ in XCTFail("closed"); return .accepted })
            XCTAssertFalse(queue.isOpen)
            XCTAssertEqual(queue.pendingCount, 0)
        }
    }

    func testUnknownControlUpdateDrainsWithoutPublishing() throws {
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let event = ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown,
            isAutoRepeat: false, modifiers: ModifierSet(), source: .ordinaryObserved,
            generation: queue.generation)
        XCTAssertEqual(queue.handoff(event), .accepted)
        queue.install(.safe, for: queue.generation)
        XCTAssertEqual(queue.pendingCount, 1)
        queue.install(GateInputs(foreground: .attributable(bundleID: "test.app")), for: queue.generation)
        XCTAssertFalse(queue.isOpen)
        XCTAssertFalse(queue.deliverOne { _ in XCTFail("unknown"); return .accepted })
    }
}
