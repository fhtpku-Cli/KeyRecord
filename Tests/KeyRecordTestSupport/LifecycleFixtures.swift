import Foundation
import KeyRecordCore

public enum FakeLifecycleFailure: Error, Sendable { case forced }

public actor InMemoryPreferencesStorage: EncryptedPreferencesStorage {
    public private(set) var ciphertext: Data?
    public private(set) var loadCount = 0
    public private(set) var saveCount = 0
    public private(set) var savedCiphertexts: [Data] = []
    public var loadFailure: PreferencesRepositoryError?
    public var saveFailure: PreferencesRepositoryError?
    public var failingSaveAttempts: Set<Int>

    public init(ciphertext: Data? = nil, loadFailure: PreferencesRepositoryError? = nil,
                saveFailure: PreferencesRepositoryError? = nil, failingSaveAttempts: Set<Int> = []) {
        self.ciphertext = ciphertext
        self.loadFailure = loadFailure
        self.saveFailure = saveFailure
        self.failingSaveAttempts = failingSaveAttempts
    }

    public func seed(ciphertext: Data?) { self.ciphertext = ciphertext }

    public func loadCiphertext() throws -> Data? {
        loadCount += 1
        if let loadFailure { throw loadFailure }
        return ciphertext
    }

    public func saveCiphertext(_ data: Data) throws {
        saveCount += 1
        savedCiphertexts.append(data)
        if let saveFailure { throw saveFailure }
        if failingSaveAttempts.contains(saveCount) { throw PreferencesRepositoryError.storageUnavailable }
        ciphertext = data
    }
}

public actor CountingLifecycleKeys: LifecycleKeyProviding {
    public private(set) var provisionCount = 0
    public var failure: LifecycleKeyError?

    public init(failure: LifecycleKeyError? = nil) { self.failure = failure }

    public func provisionAfterConsent() async throws {
        provisionCount += 1
        if let failure { throw failure }
    }
}

public actor CountingLifecycleCapture: LifecycleCaptureControlling {
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var startFailure: LifecycleCaptureError?

    public init(startFailure: LifecycleCaptureError? = nil) { self.startFailure = startFailure }

    public func setStartFailure(_ failure: LifecycleCaptureError?) { startFailure = failure }

    public func start() async throws {
        startCount += 1
        if let startFailure { throw startFailure }
    }

    public func stop() async { stopCount += 1 }
}

public actor CountingLifecycleFlush: LifecycleFlushing {
    public private(set) var flushCount = 0
    public var failure: LifecycleFlushError?

    public init(failure: LifecycleFlushError? = nil) { self.failure = failure }

    public func flushWhileUnlocked() async throws {
        flushCount += 1
        if let failure { throw failure }
    }
}

public actor FakeRestartReadiness: RestartReadinessChecking {
    public private(set) var checkCount = 0
    public private(set) var result: Result<RuntimeConditions, LifecycleReadinessError>

    public init(result: Result<RuntimeConditions, LifecycleReadinessError>) {
        self.result = result
    }

    public func setResult(_ result: Result<RuntimeConditions, LifecycleReadinessError>) {
        self.result = result
    }

    public func verifyRestartReadiness() async throws -> RuntimeConditions {
        checkCount += 1
        switch result {
        case .success(let conditions): return conditions
        case .failure(let error): throw error
        }
    }
}

public actor CountingLoginItemBackend: LoginItemBackend {
    public private(set) var registerCount = 0
    public private(set) var unregisterCount = 0
    public var registerFailure: LoginItemSystemRejection?
    public var unregisterFailure: LoginItemSystemRejection?

    public init(registerFailure: LoginItemSystemRejection? = nil,
                unregisterFailure: LoginItemSystemRejection? = nil) {
        self.registerFailure = registerFailure
        self.unregisterFailure = unregisterFailure
    }

    public func register() async throws {
        registerCount += 1
        if let registerFailure { throw registerFailure }
    }

    public func unregister() async throws {
        unregisterCount += 1
        if let unregisterFailure { throw unregisterFailure }
    }
}
