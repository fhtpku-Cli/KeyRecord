import Foundation

/// Classification of a scanned filesystem entry during local-deletion planning.
public enum DeletionEntryKind: Equatable, Sendable {
    /// Envelope file the store owns and accounts for.
    case ownedFile
    /// File inside the owned root the store cannot account for. Retained in the
    /// proceed list so the executor can report it per item.
    case unrecognizedOwnedFile
    /// Symbolic link. Never traversed or removed; its presence blocks deletion.
    case symlink
    /// Entry owned by another component; deletion must not touch it.
    case foreignEntry
    /// Directory nested inside the owned root.
    case directory
}

/// One scanned deletion candidate. `path` is the raw absolute path string; the
/// planner normalizes it lexically and never touches the filesystem.
public struct DeletionEntry: Equatable, Sendable {
    public let path: String
    public let kind: DeletionEntryKind

    public init(path: String, kind: DeletionEntryKind) {
        self.path = path
        self.kind = kind
    }
}

/// Reason deletion cannot proceed as planned.
public enum DeletionBlock: Equatable, Sendable {
    /// A symbolic link exists at the given path.
    case symlinkPresent(String)
    /// An entry owned by another component exists at the given path.
    case foreignEntryPresent(String)
    /// The entry path does not resolve strictly underneath the owned root.
    case pathOutsideOwnedRoot(String)
    /// The entry could not be read during scanning.
    case unreadableEntry(String)
}

/// Identifier for one atomic deletion action in the execution slice.
public struct DeletionStep: Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// Per-step result reported by the deletion executor (later slice).
public enum DeletionOutcome: Equatable, Sendable {
    case succeeded
    case alreadyAbsent
    case missingKeyDuringDeletion(UInt32)
    case ioFailure(String)
}

/// The planner verdict: stop and surface blocks, or remove exactly the listed entries.
public enum DeletionDecision: Equatable, Sendable {
    case blocked([DeletionBlock])
    case proceed([DeletionEntry])
}

/// Typed failure surface for the deletion ports and coordinator.
public enum DeletionError: Error, Equatable, Sendable {
    /// An owned keychain item was already gone when deletion reached it.
    case missingOwnedKey(String)
    /// A filesystem or login-item operation failed with a diagnostic message.
    case ioFailure(String)
    /// Planning refused to perform any destructive action for these reasons.
    case blocked([DeletionBlock])
}

/// Pure deletion planning: decides whether scanned entries are safe to remove.
/// No Security, filesystem, or other system APIs are called.
public enum DeletionPlanner {
    /// Evaluate scanned entries against the owned root.
    ///
    /// - Any symlink blocks with `.symlinkPresent`; any foreign entry blocks with
    ///   `.foreignEntryPresent`; any path that lexical normalization places outside
    ///   the root (including `..` escapes and sibling directories) blocks with
    ///   `.pathOutsideOwnedRoot`. All applicable blocks are returned, in entry order.
    /// - Otherwise (only owned files, unrecognized owned files, and directories, all
    ///   strictly inside the root) returns `.proceed` with the original entry list,
    ///   unrecognized entries retained in order. An empty root proceeds with `[]`.
    public static func evaluate(ownedRoot: String, entries: [DeletionEntry]) -> DeletionDecision {
        guard let root = normalizedComponents(ownedRoot) else {
            return .blocked(entries.map { .pathOutsideOwnedRoot($0.path) })
        }

        var blocks: [DeletionBlock] = []
        for entry in entries {
            if !isWithin(root: root, path: entry.path) {
                blocks.append(.pathOutsideOwnedRoot(entry.path))
            }
            switch entry.kind {
            case .symlink:
                blocks.append(.symlinkPresent(entry.path))
            case .foreignEntry:
                blocks.append(.foreignEntryPresent(entry.path))
            case .ownedFile, .unrecognizedOwnedFile, .directory:
                break
            }
        }
        return blocks.isEmpty ? .proceed(entries) : .blocked(blocks)
    }

    /// Lexically split a path into components: empty segments (leading/trailing or
    /// duplicate slashes) and `.` segments are dropped; a `..` segment is rejected
    /// outright because resolving it requires real filesystem state.
    private static func normalizedComponents(_ path: String) -> [String]? {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                return nil
            default:
                components.append(String(component))
            }
        }
        return components
    }

    /// True iff `path` normalizes successfully and sits strictly below `root`,
    /// matching complete path segments (so `/a/store2` is not inside `/a/store`).
    private static func isWithin(root: [String], path: String) -> Bool {
        guard let components = normalizedComponents(path),
              components.count > root.count
        else { return false }
        return components.prefix(root.count).elementsEqual(root)
    }
}
