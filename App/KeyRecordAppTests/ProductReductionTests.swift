import Foundation
import XCTest
import KeyRecordCore
import KeyRecordCapture
import KeyRecordStore

final class ProductReductionTests: XCTestCase {
    func testRecoveryAttributesTheNextChordToTheFreshForeground() throws {
        // Given: one chord attributed to foreground A in source generation 11.
        let reduction = makeReduction()
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app.A"),
                       generation: CaptureGeneration(rawValue: 11))
        XCTAssertEqual(reduction.deliver(try chordEvent(generation: 11)), .accepted)

        // When: recovery establishes a new source generation with foreground B.
        XCTAssertTrue(reduction.resume(inputs: inputs(bundleID: "test.app.B"),
                                       generation: CaptureGeneration(rawValue: 24)))
        XCTAssertEqual(reduction.deliver(try chordEvent(generation: 24)), .accepted)

        // Then: the retained A count and new B count occupy their own app buckets.
        let aggregate = try XCTUnwrap(reduction.snapshot())
        XCTAssertEqual(total(in: aggregate, bundleID: "test.app.A"), 1)
        XCTAssertEqual(total(in: aggregate, bundleID: "test.app.B"), 1)
    }

    func testRecoveryClearsHeldStateSoTheSameKeyCountsInTheNewSession() throws {
        // Given: a keyDown is still held when generation 7 ends.
        let reduction = makeReduction()
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app"),
                       generation: CaptureGeneration(rawValue: 7))
        XCTAssertEqual(reduction.deliver(try bareEvent(generation: 7)), .accepted)

        // When: generation 8 starts without a matching keyUp and sees the same keyDown.
        XCTAssertTrue(reduction.resume(inputs: inputs(bundleID: "test.app"),
                                       generation: CaptureGeneration(rawValue: 8)))
        XCTAssertEqual(reduction.deliver(try bareEvent(generation: 8)), .accepted)

        // Then: the new physical press is counted instead of suppressed as still held.
        let aggregate = try XCTUnwrap(reduction.snapshot())
        XCTAssertEqual(aggregate.bareKeyTotal, 2)
    }

    func testReducerRejectsAnEventFromAnOlderSourceGeneration() throws {
        // Given: reduction is bound to source generation 30.
        let reduction = makeReduction()
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app"),
                       generation: CaptureGeneration(rawValue: 30))

        // When: an event from generation 29 reaches the reducer boundary.
        let result = reduction.deliver(try bareEvent(generation: 29))

        // Then: it is rejected and cannot alter the aggregate.
        XCTAssertEqual(result, .closed)
        XCTAssertEqual(try XCTUnwrap(reduction.snapshot()).bareKeyTotal, 0)
    }

    #if DEBUG
    func testDiagnosticsCountNormalizerOutputsButOnlyRealAggregateDeltas() throws {
        // Given: a session with DEBUG reduction diagnostics attached.
        let reduction = makeReduction()
        let diagnostics = CaptureDiagnosticsRecorder()
        reduction.configureDiagnostics(diagnostics)
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app"),
                       generation: CaptureGeneration(rawValue: 12))

        // When: keyUp and repeat normalize, while only the first keyDown changes the total.
        XCTAssertEqual(reduction.deliver(try event(kind: .keyUp, generation: 12)), .accepted)
        XCTAssertEqual(reduction.deliver(try event(kind: .keyDown, generation: 12)), .accepted)
        XCTAssertEqual(reduction.deliver(try event(kind: .keyDown, repeat: true,
                                                   generation: 12)), .accepted)

        // Then: diagnostics distinguish reducer activity from a stored-count increment.
        XCTAssertEqual(diagnostics.snapshot.normalizationOutput, 3)
        XCTAssertEqual(diagnostics.snapshot.aggregateDelta, 1)
        XCTAssertEqual(try XCTUnwrap(reduction.take()).totalCount, 1)
        XCTAssertNil(try reduction.take())
    }
    #endif

    func testRecoveryRestagesRetainedCountsAcrossSchedulerReopen() async throws {
        // Given: a counted event was staged before scheduler recovery cleared pending work.
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let writer = RecordingReductionWriter()
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        try await scheduler.reopen()
        let reduction = ProductReduction(gate: gate)
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app.A"),
                       generation: CaptureGeneration(rawValue: 4))
        XCTAssertEqual(reduction.deliver(try bareEvent(generation: 4)), .accepted)
        XCTAssertTrue(reduction.hasUnflushedChanges())
        try await scheduler.stage(AggregatePersistence.objects(try XCTUnwrap(reduction.take())))
        XCTAssertFalse(reduction.hasUnflushedChanges())
        XCTAssertNil(try reduction.take())

        // When: the scheduler and capture session reopen and no new event follows.
        try await scheduler.reopen()
        XCTAssertTrue(reduction.resume(inputs: inputs(bundleID: "test.app.B"),
                                       generation: CaptureGeneration(rawValue: 9)))
        XCTAssertTrue(reduction.hasUnflushedChanges())
        try await scheduler.stage(AggregatePersistence.objects(try XCTUnwrap(reduction.take())))
        XCTAssertFalse(reduction.hasUnflushedChanges())
        try await scheduler.flushWhileUnlocked()

        // Then: the replacement writer receives the retained count without another key event.
        let objects = await writer.objects
        let rows = try objects.flatMap { try JSONDecoder().decode([DailyBareKeyAggregate].self,
                                                                  from: $0.payload) }
        XCTAssertEqual(rows.reduce(0) { $0 + $1.sourceCounts.total.value }, 1)
    }

    func testFailedRecoveryBeforePreparedSessionKeepsRetainedCountDirty() async throws {
        // Given: the only unsaved count has moved into the scheduler's pending generation.
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        let writer = RecordingReductionWriter()
        let scheduler = FlushScheduler(gate: gate, writer: writer, clock: SystemFlushClock())
        try await scheduler.reopen()
        let reduction = ProductReduction(gate: gate)
        reduction.open(AggregationReducer(cycleID: CycleID(rawValue: "cycle")),
                       inputs: inputs(bundleID: "test.app.A"),
                       generation: CaptureGeneration(rawValue: 4))
        XCTAssertEqual(reduction.deliver(try bareEvent(generation: 4)), .accepted)
        try await scheduler.stage(AggregatePersistence.objects(try XCTUnwrap(reduction.take())))
        XCTAssertFalse(reduction.hasUnflushedChanges())

        // When: recovery protects retained totals, reopens the scheduler, then source
        // qualification fails before a prepared-session callback can call resume.
        XCTAssertTrue(reduction.prepareForSchedulerReopen())
        try await scheduler.reopen()

        // Then: quit truth still sees unsaved data, and it can be staged and flushed later.
        XCTAssertTrue(reduction.hasUnflushedChanges())
        try await scheduler.stage(AggregatePersistence.objects(try XCTUnwrap(reduction.take())))
        try await scheduler.flushWhileUnlocked()
        let objects = await writer.objects
        let rows = try objects.flatMap { try JSONDecoder().decode([DailyBareKeyAggregate].self,
                                                                  from: $0.payload) }
        XCTAssertEqual(rows.reduce(0) { $0 + $1.sourceCounts.total.value }, 1)
    }

    private func makeReduction() -> ProductReduction {
        let gate = KeyAvailabilityGate()
        gate.update(.unlocked)
        return ProductReduction(gate: gate)
    }

    private func inputs(bundleID: String) -> GateInputs {
        GateInputs(collecting: true, keyAvailability: .available, sessionLock: .unlocked,
                   secureInput: .disabled, foreground: .attributable(bundleID: bundleID),
                   exclusion: .included)
    }

    private func bareEvent(generation: UInt64) throws -> ObservedKeyEvent {
        try event(kind: .keyDown, generation: generation)
    }

    private func event(kind: KeyEventKind, repeat isAutoRepeat: Bool = false,
                       generation: UInt64) throws -> ObservedKeyEvent {
        ObservedKeyEvent(keyCode: try KeyCode(4), kind: kind, isAutoRepeat: isAutoRepeat,
                         modifiers: ModifierSet(command: .none, option: .none, control: .none,
                                                shift: .none, fn: .none),
                         source: .ordinaryObserved,
                         generation: CaptureGeneration(rawValue: generation))
    }

    private func chordEvent(generation: UInt64) throws -> ObservedKeyEvent {
        ObservedKeyEvent(keyCode: try KeyCode(8), kind: .keyDown, isAutoRepeat: false,
                         modifiers: ModifierSet(command: .left, option: .none, control: .none,
                                                shift: .none, fn: .none),
                         source: .ordinaryObserved,
                         generation: CaptureGeneration(rawValue: generation))
    }

    private func total(in snapshot: AggregateSnapshot, bundleID: String) -> Int64 {
        snapshot.rows.reduce(0) { total, row in
            guard case .shortcut(let bucket) = row.identity,
                  bucket.appBucket == .bundleID(bundleID) else { return total }
            return total + row.total
        }
    }
}

private actor RecordingReductionWriter: FlushWriting {
    private(set) var objects: [FlushObject] = []

    func write(_ objects: [FlushObject], generation: CaptureGeneration) async throws {
        self.objects = objects
    }
}
