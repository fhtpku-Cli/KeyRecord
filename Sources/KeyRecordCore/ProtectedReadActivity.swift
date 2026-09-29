#if DEBUG
import Foundation

public struct ProtectedReadActivitySnapshot: Encodable, Equatable, Sendable {
    public var decryptionStarted: Int64 = 0
    public var decryptionCompleted: Int64 = 0
    public var keychainReadStarted: Int64 = 0
    public var keychainReadCompleted: Int64 = 0
}

/// Process-wide counts include all stores, so another store cannot hide a read during
/// a closed interval. Completion is separate because a read can cross its boundary.
public final class ProtectedReadActivity: @unchecked Sendable {
    public static let process = ProtectedReadActivity()
    public enum Kind: Sendable { case decryption, keychain }

    private let lock = NSLock()
    private var counts: ProtectedReadActivitySnapshot
    private var overflowed = false

    public init() { counts = ProtectedReadActivitySnapshot() }
    init(initial: ProtectedReadActivitySnapshot) { counts = initial }

    public var snapshot: ProtectedReadActivitySnapshot? {
        lock.withLock { overflowed ? nil : counts }
    }

    public func observe<T>(_ kind: Kind, _ operation: () throws -> T) rethrows -> T {
        increment(kind, completed: false)
        defer { increment(kind, completed: true) }
        return try operation()
    }

    private func increment(_ kind: Kind, completed: Bool) {
        lock.withLock {
            guard !overflowed else { return }
            let key: WritableKeyPath<ProtectedReadActivitySnapshot, Int64>
            switch (kind, completed) {
            case (.decryption, false): key = \.decryptionStarted
            case (.decryption, true): key = \.decryptionCompleted
            case (.keychain, false): key = \.keychainReadStarted
            case (.keychain, true): key = \.keychainReadCompleted
            }
            let (value, overflow) = counts[keyPath: key].addingReportingOverflow(1)
            overflowed = overflow
            if !overflow { counts[keyPath: key] = value }
        }
    }
}
#endif
