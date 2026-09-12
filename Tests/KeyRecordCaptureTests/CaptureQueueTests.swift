import XCTest
import KeyRecordCore
@testable import KeyRecordCapture

final class CaptureQueueTests: XCTestCase {
    func testCapacity4095And4096ThenOverflow4097() throws {
        // Given
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let event = try event(queue.generation)
        // When / Then: exact fixed capacity.
        for _ in 0..<4095 { XCTAssertEqual(queue.handoff(event), .accepted) }
        XCTAssertEqual(queue.pendingCount, 4095)
        XCTAssertEqual(queue.handoff(event), .accepted)
        XCTAssertEqual(queue.pendingCount, 4096)
        XCTAssertEqual(queue.handoff(event), .overflow)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertFalse(queue.isOpen)
        XCTAssertNotEqual(queue.generation, event.generation)
        XCTAssertNil(queue.reduceOne())
    }

    func testOldEventCannotPublishAfterRevokeOrReopen() throws {
        // Given
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let old = try event(queue.generation)
        XCTAssertEqual(queue.handoff(old), .accepted)
        // When
        queue.revoke()
        queue.install(.safe, for: queue.generation)
        // Then
        XCTAssertEqual(queue.handoff(old), .closed)
        XCTAssertNil(queue.reduceOne())
    }

    func testFreshEventAndMetadataShareGeneration() throws {
        // Given
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        // When
        XCTAssertEqual(queue.handoff(try event(queue.generation)), .accepted)
        let output = try XCTUnwrap(queue.reduceOne())
        // Then
        XCTAssertEqual(output.generation, queue.generation)
        XCTAssertEqual(output.foreground, .attributable(bundleID: "test.app"))
    }

    func testStaleRefreshCannotOpenGate() {
        // Given
        let queue = CaptureQueue()
        let generation = queue.generation
        // When
        queue.revoke()
        queue.install(.safe, for: generation)
        // Then
        XCTAssertFalse(queue.isOpen)
        XCTAssertEqual(queue.snapshot.foreground, .unknown)
    }

    func testForegroundBoundaryMismatchRevokesQueuedEvents() throws {
        // Given
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        XCTAssertEqual(queue.handoff(try event(queue.generation)), .accepted)
        // When
        queue.install(GateInputs(collecting: true, keyAvailability: .available,
            sessionLock: .unlocked, secureInput: .disabled,
            foreground: .attributable(bundleID: "other.app"), exclusion: .included), for: queue.generation)
        // Then
        XCTAssertFalse(queue.isOpen)
        XCTAssertNil(queue.reduceOne())
    }

    func testResetClearsModifiersBeforeReopen() throws {
        // Given
        let queue = CaptureQueue()
        queue.install(.safe, for: queue.generation)
        let held = ObservedKeyEvent(keyCode: try KeyCode(55), kind: .flagsChanged,
            isAutoRepeat: false, modifiers: ModifierSet(command: .left),
            source: .ordinaryObserved, generation: queue.generation)
        XCTAssertEqual(queue.handoff(held), .accepted)
        _ = queue.reduceOne()
        // When
        queue.revoke()
        queue.install(.safe, for: queue.generation)
        // Then
        XCTAssertEqual(queue.modifiers, ModifierSet())
        XCTAssertEqual(queue.handoff(try event(queue.generation)), .accepted)
        XCTAssertNotNil(queue.reduceOne())
    }

    private func event(_ generation: CaptureGeneration) throws -> ObservedKeyEvent {
        ObservedKeyEvent(keyCode: try KeyCode(0), kind: .keyDown, isAutoRepeat: false,
            modifiers: ModifierSet(), source: .ordinaryObserved, generation: generation)
    }
}

extension GateInputs {
    static var safe: GateInputs {
        GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
            secureInput: .disabled, foreground: .attributable(bundleID: "test.app"), exclusion: .included)
    }
}
