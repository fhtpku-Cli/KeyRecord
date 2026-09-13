import Foundation

/// Filesystem surface used by the deletion coordinator. The real adapter lands in a
/// later slice; tests substitute an in-memory fake.
public protocol DeletionFileSystem: Sendable {
    func listOwnedEntries(ownedRoot: String) async throws -> [DeletionEntry]
    func removeOwnedEntry(_ entry: DeletionEntry) async throws
    func ownedRootExists(_ root: String) async -> Bool
    func removeOwnedRootIfEmpty(_ root: String) async throws
}

/// Owned keychain item surface. Items are identified by their account string
/// (the real adapter uses `KeychainItemID.account`, e.g. `master-v3`).
public protocol DeletionKeychain: Sendable {
    func ownedVersionedItemIDs() async throws -> [String]
    func deleteOwnedItem(_ id: String) async throws
}

/// Login-item registration surface. Returns the outcome rather than throwing for
/// the already-absent case so repeat deletions converge without error-as-control-flow.
public protocol DeletionLoginItems: Sendable {
    func unregisterProductLoginItem() async throws -> DeletionOutcome
}

/// Result of one complete deletion pass.
public struct DeletionReport: Equatable, Sendable {
    public let decision: DeletionDecision
    public private(set) var fileOutcomes: [String: DeletionOutcome]
    public private(set) var keyOutcomes: [String: DeletionOutcome]
    public let loginItemOutcome: DeletionOutcome

    /// A deletion pass always invalidates consent; any future store use needs it anew.
    public var requiresFreshConsent: Bool { true }

    /// Success means no planning block (blocked passes throw instead) and no I/O
    /// failure. A key already absent during deletion is a destroyed-credential
    /// outcome, not an I/O failure, so it does not flip this to false.
    public var succeeded: Bool {
        var failed = false
        for outcome in fileOutcomes.values where outcome.isIOFailure { failed = true }
        for outcome in keyOutcomes.values where outcome.isIOFailure { failed = true }
        if loginItemOutcome.isIOFailure { failed = true }
        return !failed
    }
}

extension DeletionOutcome {
    var isIOFailure: Bool {
        if case .ioFailure = self { return true }
        return false
    }
}

/// Orchestrates explicit local-data deletion through injected ports. Reentrant:
/// the actor serializes passes, and each pass converges against current state.
public actor LocalDeletionCoordinator {
    private let ownedRoot: String
    private let fileSystem: DeletionFileSystem
    private let keychain: DeletionKeychain
    private let loginItems: DeletionLoginItems

    public init(
        ownedRoot: String,
        fileSystem: DeletionFileSystem,
        keychain: DeletionKeychain,
        loginItems: DeletionLoginItems
    ) {
        self.ownedRoot = ownedRoot
        self.fileSystem = fileSystem
        self.keychain = keychain
        self.loginItems = loginItems
    }

    /// Delete all owned key material, owned files, the empty root directory, and the
    /// product login item. Throws `DeletionError.blocked` before touching any state
    /// when planning refuses; per-item failures are collected into the report and the
    /// pass continues, so a re-run after repair converges.
    public func deleteEverything() async throws -> DeletionReport {
        let entries = try await fileSystem.listOwnedEntries(ownedRoot: ownedRoot)
        let decision = DeletionPlanner.evaluate(ownedRoot: ownedRoot, entries: entries)
        if case .blocked(let blocks) = decision {
            throw DeletionError.blocked(blocks)
        }

        let keyOutcomes = try await deleteOwnedKeys()
        let fileOutcomes = await deleteOwnedFiles(entries)
        let loginOutcome = await unregisterLoginItem()
        return DeletionReport(
            decision: decision,
            fileOutcomes: fileOutcomes,
            keyOutcomes: keyOutcomes,
            loginItemOutcome: loginOutcome)
    }

    private func deleteOwnedKeys() async throws -> [String: DeletionOutcome] {
        var outcomes: [String: DeletionOutcome] = [:]
        let keyIDs = try await keychain.ownedVersionedItemIDs()
        for id in keyIDs {
            do {
                try await keychain.deleteOwnedItem(id)
                outcomes[id] = .succeeded
            } catch DeletionError.missingOwnedKey {
                // Already destroyed is destruction, not a read/recovery failure:
                // the key cannot decrypt anything anymore, so deletion converged.
                outcomes[id] = .missingKeyDuringDeletion(Self.keyVersionSuffix(of: id))
            } catch {
                outcomes[id] = .ioFailure(Self.errorMessage(error))
            }
        }
        return outcomes
    }

    private func deleteOwnedFiles(_ entries: [DeletionEntry]) async -> [String: DeletionOutcome] {
        var outcomes: [String: DeletionOutcome] = [:]
        var sawIOFailure = false
        for entry in entries {
            do {
                try await fileSystem.removeOwnedEntry(entry)
                outcomes[entry.path] = .succeeded
            } catch DeletionError.ioFailure(let message) {
                outcomes[entry.path] = .ioFailure(message)
                sawIOFailure = true
            } catch {
                outcomes[entry.path] = .ioFailure(Self.errorMessage(error))
                sawIOFailure = true
            }
        }
        // Only a fully emptied root may be removed; a failed entry keeps it on disk.
        guard !sawIOFailure else { return outcomes }
        if await fileSystem.ownedRootExists(ownedRoot) {
            do {
                try await fileSystem.removeOwnedRootIfEmpty(ownedRoot)
                outcomes[ownedRoot] = .succeeded
            } catch {
                outcomes[ownedRoot] = .ioFailure(Self.errorMessage(error))
            }
        } else {
            outcomes[ownedRoot] = .alreadyAbsent
        }
        return outcomes
    }

    private func unregisterLoginItem() async -> DeletionOutcome {
        do {
            return try await loginItems.unregisterProductLoginItem()
        } catch {
            return .ioFailure("loginItem")
        }
    }

    private static func keyVersionSuffix(of id: String) -> UInt32 {
        var digits = ""
        for character in id.reversed() {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { break }
            digits.insert(character, at: digits.startIndex)
        }
        return UInt32(digits) ?? 0
    }

    private static func errorMessage(_ error: Error) -> String {
        if case DeletionError.ioFailure(let message) = error { return message }
        return String(describing: error)
    }
}
