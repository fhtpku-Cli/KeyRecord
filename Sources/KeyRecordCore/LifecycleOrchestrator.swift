import Foundation

/// All side effects for lifecycle orchestration. Fakes stand in for tasks 11/12/13; task 19 composes real ones.
public struct LifecyclePorts: Sendable {
    public let preferences: any PreferencesPersisting
    public let keys: any LifecycleKeyProviding
    public let capture: any LifecycleCaptureControlling
    public let flush: any LifecycleFlushing
    public let readiness: any RestartReadinessChecking
    public let login: any LoginItemBackend
    public let cycleIDs: any CycleIDGenerator

    public init(preferences: any PreferencesPersisting, keys: any LifecycleKeyProviding,
                capture: any LifecycleCaptureControlling, flush: any LifecycleFlushing,
                readiness: any RestartReadinessChecking, login: any LoginItemBackend,
                cycleIDs: any CycleIDGenerator) {
        self.preferences = preferences
        self.keys = keys
        self.capture = capture
        self.flush = flush
        self.readiness = readiness
        self.login = login
        self.cycleIDs = cycleIDs
    }
}

/// Async shell around the pure `reduce` FSM. Every state change originates here or in a port completion;
/// the reducer alone decides ordering, so side-effect counts in fakes prove the consent/flush contracts.
@MainActor
public final class LifecycleOrchestrator {
    public internal(set) var state = LifecycleState.initial
    private let ports: LifecyclePorts

    public init(ports: LifecyclePorts) {
        self.ports = ports
    }

    public var phase: LifecyclePhase { state.phase }

    public func requestConsent() {
        dispatch(.consentRequested)
    }

    public func acceptConsent() async {
        let cycleID = await ports.cycleIDs.nextCycleID()
        await run(.consentAccepted(cycleID: cycleID))
    }

    public func denyConsent() {
        dispatch(.consentDenied)
    }

    public func pause() async {
        await run(.pauseRequested)
    }

    public func resume() async {
        await run(.resumeRequested)
    }

    public func quit() async {
        await run(.quitRequested)
    }

    public func retry() async {
        await run(.retry)
    }

    public func reload(afterMaintenance: Bool = false) async {
        do {
            let preferences = try await (afterMaintenance
                ? ports.preferences.reloadAfterMaintenance() : ports.preferences.load())
            await run(.reload(preferences))
        } catch let error as PreferencesRepositoryError {
            await run(.reloadFailed(Self.storeError(error)))
        } catch {
            await run(.reloadFailed(.protectedDataUnavailable))
        }
    }

    public func setExclusions(_ excludedBundleIDs: Set<String>) async {
        await run(.exclusionsChanged(excludedBundleIDs))
    }

    public func setLoginItem(enabled: Bool) async {
        await run(.loginItemSetEnabled(enabled))
    }

    public func observe(_ conditions: RuntimeConditions) {
        dispatch(.conditionsChanged(conditions))
    }

    public func dismissNotice() {
        dispatch(.dismissNotice)
    }

    @discardableResult
    private func dispatch(_ event: LifecycleEvent) -> [LifecycleEffect] {
        let outcome = reduce(state, event)
        state = outcome.state
        return outcome.effects
    }

    private func run(_ event: LifecycleEvent) async {
        await execute(dispatch(event))
    }

    private func execute(_ effects: [LifecycleEffect]) async {
        for effect in effects {
            await executeOne(effect)
        }
    }

    private func executeOne(_ effect: LifecycleEffect) async {
        switch effect {
        case .provisionKey:
            do {
                try await ports.keys.provisionAfterConsent()
                await finish(.keyProvisioned)
            } catch let error as LifecycleKeyError {
                await finish(.keyProvisionFailed(error))
            } catch {
                await finish(.keyProvisionFailed(.unavailable))
            }
        case .persistPreferences:
            await persistPreferences()
        case .startCapture:
            do {
                try await ports.capture.start()
                await finish(.captureStarted)
            } catch let error as LifecycleCaptureError {
                await finish(.captureStartDenied(error))
            } catch {
                await finish(.captureStartDenied(.runtimeFailed))
            }
        case .stopCapture:
            await ports.capture.stop()
            switch state.phase {
            case .pausing: await finish(.pauseRuntimeStopped)
            case .stopping: await finish(.quitRuntimeStopped)
            default: break
            }
        case .flushWhileUnlocked:
            await flush()
        case .verifyRestartReadiness:
            do {
                let conditions = try await ports.readiness.verifyRestartReadiness()
                await finish(.restartReadiness(conditions))
            } catch let error as LifecycleReadinessError {
                await finish(.restartBlocked(Self.blockedReason(error)))
            } catch {
                await finish(.restartBlocked(.keyUnavailable))
            }
        case .registerLoginItem:
            do {
                try await ports.login.register()
                await finish(.loginItemRegistered)
            } catch let rejection as LoginItemSystemRejection {
                await finish(.loginItemRegistrationRejected(rejection))
            } catch {
                await finish(.loginItemRegistrationRejected(.registrationDenied))
            }
        case .unregisterLoginItem:
            do {
                try await ports.login.unregister()
                await finish(.loginItemUnregistered)
            } catch {
                await finish(.loginItemUnregistrationRejected(.unregistrationDenied))
            }
        case .reloadFromStorage:
            await reload()
        }
    }

    private func persistPreferences() async {
        let event: LifecycleEvent
        switch state.phase {
        case .starting: event = .bootstrapPersisted
        case .pausing: event = .pausePersisted
        case .resuming: event = .resumePersisted
        default: event = .exclusionsPersisted
        }
        do {
            guard let preferences = state.preferences else {
                await finish(event)
                return
            }
            try await ports.preferences.save(preferences)
            await finish(event)
        } catch let error as PreferencesRepositoryError {
            await persistFailed(Self.storeError(error))
        } catch {
            await persistFailed(.protectedDataUnavailable)
        }
    }

    private func persistFailed(_ error: LifecycleStoreError) async {
        switch state.phase {
        case .starting: await finish(.initialPersistenceFailed(error))
        case .pausing: await finish(.pausePersistenceFailed(error))
        case .resuming: await finish(.resumePersistenceFailed(error))
        default: await finish(.exclusionsPersistFailed(error))
        }
    }

    private func flush() async {
        do {
            try await ports.flush.flushWhileUnlocked()
            switch state.phase {
            case .pausing: await finish(.pauseFlushSucceeded)
            case .stopping: await finish(.quitFlushSucceeded)
            default: break
            }
        } catch let error as LifecycleFlushError {
            switch state.phase {
            case .pausing: await finish(.pauseFlushFailed(error))
            case .stopping: await finish(.quitFlushFailed(error))
            default: break
            }
        } catch {
            switch state.phase {
            case .pausing: await finish(.pauseFlushFailed(.failed))
            case .stopping: await finish(.quitFlushFailed(.failed))
            default: break
            }
        }
    }

    private func finish(_ event: LifecycleEvent) async {
        await execute(dispatch(event))
    }

    private static func storeError(_ error: PreferencesRepositoryError) -> LifecycleStoreError {
        switch error {
        case .corruptStoredPreferences: .corruptStoredPreferences
        case .storageUnavailable: .protectedDataUnavailable
        }
    }

    private static func blockedReason(_ error: LifecycleReadinessError) -> BlockedReason {
        switch error {
        case .keyUnavailable, .queryFailed: .keyUnavailable
        case .sessionLocked: .sessionLocked
        case .secureInputActive: .secureInputActive
        case .foregroundUnreliable: .foregroundUnreliable
        }
    }
}
