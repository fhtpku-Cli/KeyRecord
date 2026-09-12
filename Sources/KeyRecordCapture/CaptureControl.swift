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
}

public struct UnqualifiedSessionLockProvider: SessionLockProvider {
    public init() {}
    public func sessionLockState() async -> SessionLockState { .unknown }
}
