import Foundation

public enum FrontmostState: Equatable, Sendable {
    case known(bundleID: String)
    case knownUnattributable
    case indeterminate
}

public enum SecureInputState: String, Codable, CaseIterable, Sendable {
    case disabled, enabled, unknown
}

public enum CaptureState: String, Codable, Sendable {
    case collecting, paused
}

public enum AppBucket: Hashable, Sendable {
    case bundle(String)
    case unknown
}

public enum PrivacyDecision: Equatable, Sendable {
    case counted(bucket: AppBucket)
    case dropped
}

public struct PrivacyTotals: Codable, Equatable, Sendable {
    public var data: Int
    public var meta: Int
    public static let zero = PrivacyTotals(data: 0, meta: 0)
}

public struct PrivacyTransitionModel: Sendable {
    public var captureState: CaptureState = .collecting
    public private(set) var totals: PrivacyTotals = .zero
    public private(set) var bucketCounts: [AppBucket: Int] = [:]
    public private(set) var generation: UInt64 = 0
    private var tapAvailable = true
    private var awake = true
    private var wakeReconstructed = true

    public init() {}

    public mutating func observeTerminalKeyDown(
        frontmost: FrontmostState,
        secureInput: SecureInputState,
        excludedBundleIDs: Set<String>
    ) -> PrivacyDecision {
        guard captureState == .collecting, tapAvailable, awake, wakeReconstructed,
              secureInput == .disabled else { return .dropped }
        let bucket: AppBucket
        switch frontmost {
        case let .known(bundleID):
            guard !bundleID.isEmpty, !excludedBundleIDs.contains(bundleID) else { return .dropped }
            bucket = .bundle(bundleID)
        case .knownUnattributable:
            bucket = .unknown
        case .indeterminate:
            return .dropped
        }
        totals.data += 1
        totals.meta += 1
        bucketCounts[bucket, default: 0] += 1
        return .counted(bucket: bucket)
    }

    public mutating func tapReset() {
        generation += 1
        tapAvailable = false
        totals = .zero
        bucketCounts.removeAll(keepingCapacity: false)
    }

    public mutating func recoverTap() { tapAvailable = true }

    public mutating func systemWillSleep() {
        awake = false
        wakeReconstructed = false
        totals = .zero
        bucketCounts.removeAll(keepingCapacity: false)
    }

    public mutating func systemDidWake() { awake = true }
    public mutating func recoverAfterWake() { wakeReconstructed = true }
}

public enum FrontmostCache {
    public static func resolve(notification: FrontmostState?, workspace: FrontmostState?) -> FrontmostState {
        guard let notification, let workspace else { return .indeterminate }
        switch (notification, workspace) {
        case let (.known(left), .known(right)) where left == right && !left.isEmpty:
            return .known(bundleID: left)
        case (.knownUnattributable, .knownUnattributable):
            return .knownUnattributable
        default:
            return .indeterminate
        }
    }
}
