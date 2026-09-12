import Foundation

public enum NormalizedKey: Equatable, Sendable {
    case bare(KeyCode)
    case chord(ChordBucket, ShortcutClassification)
}

/// Ordinary observation is not proof of authenticity. Product markers have no output variant.
public enum NormalizedSource: Equatable, Sendable {
    case ordinaryObserved, suspectedInjection
}

/// Transient reducer input, deliberately not Codable. No logging/metadata payload accompanies a drop.
/// Repeated downs are forwarded separately; first-down suppression belongs to the task-9 aggregator.
public enum NormalizationOutput: Equatable, Sendable {
    case none
    case keyDown(NormalizedKey, NormalizedSource)
    case repeatedKeyDown(KeyCode)
    case keyUp(KeyCode)

    public var sourceDelta: SourceCounts {
        get throws {
            switch self {
            case .keyDown(_, .ordinaryObserved):
                return try SourceCounts(ordinary: Count(1), suspectedInjection: Count(0))
            case .keyDown(_, .suspectedInjection):
                return try SourceCounts(ordinary: Count(0), suspectedInjection: Count(1))
            case .none, .repeatedKeyDown, .keyUp:
                return try SourceCounts(ordinary: Count(0), suspectedInjection: Count(0))
            }
        }
    }
}
