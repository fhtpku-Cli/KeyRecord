import KeyRecordCore

public enum ForegroundReading: Sendable {
    case observed(bundleID: String?)
    case failed

    public var state: ForegroundState {
        switch self {
        case .observed(let bundleID):
            guard let bundleID, !bundleID.isEmpty else { return .reliablyUnattributable }
            return .attributable(bundleID: bundleID)
        case .failed: return .unknown
        }
    }
}

public struct FallibleForegroundProvider: FrontmostAppProvider {
    private let query: @Sendable () async throws -> ForegroundReading

    public init(query: @escaping @Sendable () async throws -> ForegroundReading) { self.query = query }

    public func foregroundState() async -> ForegroundState {
        do { return try await query().state }
        catch { return .unknown }
    }
}

public struct CapturePolicy: Sendable {
    public let collecting: Bool
    public let keyAvailability: KeyAvailability
    public let exclusion: ExclusionState

    public init(collecting: Bool, keyAvailability: KeyAvailability, exclusion: ExclusionState) {
        self.collecting = collecting
        self.keyAvailability = keyAvailability
        self.exclusion = exclusion
    }
}

public struct CaptureProviderSet: Sendable {
    let foreground: any FrontmostAppProvider
    let secureInput: any SecureInputProvider
    let sessionLock: any SessionLockProvider

    public init(foreground: any FrontmostAppProvider, secureInput: any SecureInputProvider,
                sessionLock: any SessionLockProvider) {
        self.foreground = foreground
        self.secureInput = secureInput
        self.sessionLock = sessionLock
    }
}

public actor CaptureControl {
    private let queue: CaptureQueue
    private let providers: CaptureProviderSet

    public init(queue: CaptureQueue, providers: CaptureProviderSet) {
        self.queue = queue
        self.providers = providers
    }

    public func refresh(policy: CapturePolicy) async {
        queue.revoke()
        let generation = queue.generation
        let foreground = await providers.foreground.foregroundState()
        let secureInput = await providers.secureInput.secureInputState()
        let lock = await providers.sessionLock.sessionLockState()
        guard !Task.isCancelled else { return }
        queue.install(GateInputs(collecting: policy.collecting, keyAvailability: policy.keyAvailability,
            sessionLock: lock, secureInput: secureInput, foreground: foreground,
            exclusion: policy.exclusion), for: generation)
    }

    static func prepare(queue: CaptureQueue, expected: CaptureSnapshot,
                        backend: any CaptureTapBackend,
                        onInvalidation: (@Sendable (CaptureInvalidation) -> Void)? = nil)
        async throws -> CaptureSnapshot {
        let generation = queue.generation
        // KR-02: still revoke immediately (fail closed), but no longer DISCARD the reason.
        // Forwarding it lets the composition layer run one serial recovery transaction
        // instead of leaving the session dead until another full start.
        try await backend.subscribe { reason in
            queue.revoke()
            onInvalidation?(reason)
        }
        guard queue.generation == generation, !Task.isCancelled else { throw CaptureStartError.revoked }
        let current = await backend.readProviders()
        guard queue.generation == generation, current == CaptureProviderSnapshot(expected.inputs),
              !Task.isCancelled else { throw CaptureStartError.revoked }
        queue.install(expected.inputs, for: generation)
        let prepared = queue.snapshot
        guard queue.validate(prepared, current: backend.cachedProviders()) else { throw CaptureStartError.revoked }
        return prepared
    }
}

public struct UnqualifiedSessionLockProvider: SessionLockProvider {
    public init() {}
    public func sessionLockState() async -> SessionLockState { .unknown }
}
