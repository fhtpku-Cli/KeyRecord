import Foundation

// MARK: - Task 18 side-effect ports

/// Clears the day-level aggregate detail for the active cycle ("reset today").
/// Mappings, backups, preferences, and ignored recommendations are retained.
/// Faked in this slice; the real store adapter is composed in T19.
public protocol CycleResetting: Sendable {
    func performCycleReset() async throws
}

/// Irreversibly removes every local artifact: aggregates, mappings, namespace keys,
/// and the login item registration. Faked in this slice; T19 composes the real adapter.
public protocol LocalDataErasing: Sendable {
    func eraseAllLocalData() async throws
}

// MARK: - Lifecycle seam

/// Narrow slice of `LifecycleOrchestrator` consumed by the phase-1 flow model.
/// The FSM currently has no collecting/paused -> unstarted event and `state` has a
/// private setter, so direct orchestrator holding cannot re-arm consent after erasure;
/// this seam lets the model demand the re-arm without owning the mechanics.
@MainActor
public protocol LifecycleDriving: AnyObject {
    var state: LifecycleState { get }
    /// Re-arm the first-run consent gate after all local data has been erased.
    func returnToConsentRequired() async
}

extension LifecycleOrchestrator: LifecycleDriving {
    public func returnToConsentRequired() async {
        // T19 wires the real re-arm: the erasure adapter empties the store and the
        // lifecycle is rebuilt from `.initial`. Until that composition exists, reload
        // is the closest public seam (a reset/erase FSM event does not exist yet).
        await reload()
    }
}

// MARK: - Aggregate display placeholder

/// UI-facing totals placeholder for task 18. It is deliberately NOT a persisted domain
/// record: `DailyShortcutAggregate`/`DailyBareKeyAggregate` are per-day schema-bound
/// records and `CycleSummary` is a cycle document, so neither is a view DTO. The next
/// slice feeds real reducer totals into this shape.
public struct AggregateSnapshot: Equatable, Sendable {
    public let shortcutTotal: Int64
    public let bareKeyTotal: Int64

    public init(shortcutTotal: Int64, bareKeyTotal: Int64) {
        self.shortcutTotal = shortcutTotal
        self.bareKeyTotal = bareKeyTotal
    }
}

// MARK: - Sensitive content visibility

public enum SensitiveVisibility {
    /// Sensitive aggregates are visible only in the two steady-state usage phases
    /// (collecting/paused) with no sensitive gate closure. Hidden while the session is
    /// locked, secure input is active, provider state is unknown/unreliable, the key is
    /// unavailable, the gate is reset/exhausted, any block is pending, an error is set,
    /// and before consent (unstarted/consent/transient/stopped phases).
    public static func isVisible(_ state: LifecycleState) -> Bool {
        guard state.phase == .collecting || state.phase == .paused else { return false }
        // A pending provider block (lock/secure input/unknown foreground) hides content.
        guard state.blockedReason == nil else { return false }
        // `.notCollecting` is the paused steady state; `.excluded` only suspends
        // attribution for the foreground app, so neither hides retained totals.
        switch state.gate.closureReason {
        case nil, .some(.notCollecting), .some(.excluded):
            return true
        case .some(.sessionLocked), .some(.secureInput), .some(.keyUnavailable),
             .some(.foregroundUnreliable), .some(.reset), .some(.generationExhausted):
            return false
        }
    }
}

// MARK: - Phase 1 flow model

/// @MainActor state layer for the task 18 reset/delete screens. Pure Foundation: the
/// SwiftUI screens arrive in the next slice and observe `onChange` snapshots.
@MainActor
public final class Phase1FlowModel {
    public private(set) var dialog: FlowDialog = .none
    public var onChange: (@MainActor () -> Void)?

    private let lifecycle: any LifecycleDriving
    private let cycleReset: (any CycleResetting)?
    private let localDataEraser: (any LocalDataErasing)?
    private var rawAggregate: AggregateSnapshot?

    public init(lifecycle: any LifecycleDriving,
                cycleReset: (any CycleResetting)? = nil,
                localDataEraser: (any LocalDataErasing)? = nil) {
        self.lifecycle = lifecycle
        self.cycleReset = cycleReset
        self.localDataEraser = localDataEraser
    }

    /// Derived straight from lifecycle state; never a separately persisted flag.
    public var sensitiveContentVisible: Bool { SensitiveVisibility.isVisible(lifecycle.state) }

    /// Raw totals are retained while hidden; the getter gates them on visibility so a
    /// locked/error screen can never render sensitive aggregate content.
    public var displayedAggregate: AggregateSnapshot? {
        get { sensitiveContentVisible ? rawAggregate : nil }
        set {
            rawAggregate = newValue
            onChange?()
        }
    }

    /// Reset is requestable only from the two steady usage phases; otherwise the
    /// currently presented dialog (if any) is left untouched.
    public func requestReset() {
        let phase = lifecycle.state.phase
        guard phase == .collecting || phase == .paused else { return }
        present(.resetConfirmation(.standard()))
    }

    /// Delete is requestable from every post-consent phase. From `.unstarted` there is
    /// nothing to erase, so no dialog is offered.
    public func requestDeleteLocalData() {
        guard lifecycle.state.phase != .unstarted else {
            present(.none)
            return
        }
        present(.deleteConfirmation(.deleteStandard()))
    }

    public func choose(_ choice: DialogChoice) async throws {
        switch dialog {
        case .none:
            return
        case .resetConfirmation:
            switch choice {
            case .cancel:
                present(.none)
            case .confirm:
                // Port may be unwired pre-T19: the proposal is still requestable so the
                // UI can explain, but confirmation surfaces a typed unavailability.
                guard let cycleReset else { throw FlowError.actionUnavailable }
                try await cycleReset.performCycleReset()
                present(.none)
            }
        case .deleteConfirmation:
            switch choice {
            case .cancel:
                present(.none)
            case .confirm:
                guard let localDataEraser else { throw FlowError.actionUnavailable }
                try await localDataEraser.eraseAllLocalData()
                await lifecycle.returnToConsentRequired()
                present(.none)
            }
        }
    }

    private func present(_ dialog: FlowDialog) {
        self.dialog = dialog
        onChange?()
    }
}
