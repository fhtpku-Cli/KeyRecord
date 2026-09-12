import Foundation
import KeyRecordCore

public enum LifecycleHarnessConditions {
    public static let open = RuntimeConditions(
        keyAvailability: .available, sessionLock: .unlocked,
        secureInput: .disabled, foreground: .attributable(bundleID: "com.ex"))
}

@MainActor
public struct LifecycleHarness {
    public let orchestrator: LifecycleOrchestrator
    public let storage: InMemoryPreferencesStorage
    public let keys: CountingLifecycleKeys
    public let capture: CountingLifecycleCapture
    public let flush: CountingLifecycleFlush
    public let readiness: FakeRestartReadiness
    public let login: CountingLoginItemBackend
    public let cycleID = CycleID(rawValue: "harness-cycle")

    public init(storage: InMemoryPreferencesStorage? = nil,
                keyFailure: LifecycleKeyError? = nil,
                captureFailure: LifecycleCaptureError? = nil,
                flushFailure: LifecycleFlushError? = nil,
                readinessResult: Result<RuntimeConditions, LifecycleReadinessError> = .success(
                    RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                                     secureInput: .disabled, foreground: .attributable(bundleID: "com.ex"))),
                loginRegisterFailure: LoginItemSystemRejection? = nil,
                loginUnregisterFailure: LoginItemSystemRejection? = nil) {
        let storage = storage ?? InMemoryPreferencesStorage()
        self.storage = storage
        repository = PreferencesRepository(storage: storage)
        keys = CountingLifecycleKeys(failure: keyFailure)
        capture = CountingLifecycleCapture(startFailure: captureFailure)
        flush = CountingLifecycleFlush(failure: flushFailure)
        readiness = FakeRestartReadiness(result: readinessResult)
        login = CountingLoginItemBackend(registerFailure: loginRegisterFailure,
                                         unregisterFailure: loginUnregisterFailure)
        orchestrator = LifecycleOrchestrator(ports: LifecyclePorts(
            preferences: repository, keys: keys, capture: capture, flush: flush,
            readiness: readiness, login: login,
            cycleIDs: FixedIDGenerator(value: CycleID(rawValue: "harness-cycle"))))
    }

    private let repository: PreferencesRepository

    public func startConsented() async {
        orchestrator.requestConsent()
        await orchestrator.acceptConsent()
    }

    public func collectOpen() async {
        await startConsented()
        orchestrator.observe(LifecycleHarnessConditions.open)
    }

    public func storedPreferences() async -> Preferences? {
        guard let ciphertext = await storage.ciphertext else { return nil }
        return try? PreferencesRepository.decode(ciphertext)
    }
}
