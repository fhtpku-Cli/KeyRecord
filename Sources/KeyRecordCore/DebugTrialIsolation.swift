#if DEBUG
import Foundation

    /// Explicit Debug-only trial location. Empty inputs keep the production store and keychain.
    /// A partial, illegal, or overlapping choice is rejected and must not fall back to production.
    /// Paths are symlink-resolved before comparison. An unchanged directory modification time
    /// does not prove the real store was never opened.
public enum DebugTrialIsolation {
    public struct Location: Equatable, Sendable {
        public var storeRoot: URL
        public var namespace: String
        public init(storeRoot: URL, namespace: String) {
            self.storeRoot = storeRoot
            self.namespace = namespace
        }
    }

    public enum Selection: Equatable, Sendable {
        case production
        case trial(Location)
        case rejected
    }

    public static let productionNamespace = "com.keyrecord.app"

    public static func select(store: String?, namespace: String?, realStoreRoot: URL) -> Selection {
        let storeValue = store?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let namespaceValue = namespace?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if storeValue.isEmpty && namespaceValue.isEmpty { return .production }
        guard !storeValue.isEmpty, !namespaceValue.isEmpty else { return .rejected }
        guard namespaceValue != productionNamespace, validNamespace(namespaceValue) else { return .rejected }
        guard storeValue.hasPrefix("/") else { return .rejected }
        let trial = URL(fileURLWithPath: storeValue).resolvingSymlinksInPath().standardizedFileURL
        let real = realStoreRoot.resolvingSymlinksInPath().standardizedFileURL
        let realOwner = real.deletingLastPathComponent().standardizedFileURL
        if trial == real || trial == realOwner { return .rejected }
        if trial.path.hasPrefix(realOwner.path + "/") || real.path.hasPrefix(trial.path + "/") {
            return .rejected
        }
        return .trial(Location(storeRoot: trial, namespace: namespaceValue))
    }

    private static func validNamespace(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            $0 == 45 || $0 == 46 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
}
#endif
