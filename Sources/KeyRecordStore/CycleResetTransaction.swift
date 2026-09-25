import Foundation
import KeyRecordCore

extension ObjectStore {
    /// Contract 9 ordered idempotent transaction. The store lease serializes every reset
    /// against key rotation; a duplicated operation ID converges to the same new cycle.
    /// The operation a durable journal already owns, or nil when no reset is pending.
    /// Throws when a journal file exists but cannot be authenticated; callers must not
    /// replace it with a new operation or report the reset finished.
    public func pendingResetOperationID() async throws -> UUID? {
        try await loadPendingResetJournals().last?.payload.operationID
    }

    /// Continues the journal's own operation when one is on disk. Returns false when there
    /// is nothing to continue. A failure leaves the journal in place.
    public func continueUnfinishedReset(day: LocalDay) async throws -> Bool {
        guard bootstrapState() == .opened else { return false }
        guard let operation = try await pendingResetOperationID() else { return false }
        _ = try await resetCycle(operationID: operation, day: day)
        return true
    }

    private func loadPendingResetJournals() async throws -> [LoadedResetJournal] {
        _ = try opened()
        let versions = try await keySource.namespaceKeyVersions()
        let raw = Set(versions.map(\.rawValue))
        var materials: [UInt32: Data] = [:]
        for version in raw.sorted() {
            materials[version] = try await material(version, versions: versions)
        }
        return try cycleJournals.load(knownVersions: raw, materials: materials)
    }

    public func resetCycle(operationID: UUID, day: LocalDay,
                           injection provided: CycleResetInjection? = nil) async throws -> CycleID {
        _ = try opened()
        let leaseID = try beginLease()
        defer { endLease(leaseID) }
        let injection = provided ?? configuredResetInjection
        let target = CycleResetIdentifiers.newCycleID(operationID: operationID)

        let keyVersions = Set((try await keySource.namespaceKeyVersions()).map(\.rawValue))
        var materials: [UInt32: Data] = [:]
        for raw in keyVersions.sorted() { materials[raw] = try await material(raw, versions: nil) }
        let pending = try cycleJournals.load(knownVersions: keyVersions, materials: materials)

        let journal: ResetJournalPayload
        if let existing = pending.last {
            guard existing.payload.operationID == operationID else {
                throw ObjectStoreError.reset(.conflictingOperation)
            }
            journal = existing.payload
        } else {
            if let current = try? currentCycleRecord(), current.cycleID == target { return target }
            journal = try await prepareJournal(operationID: operationID, target: target)
            try persistJournal(journal, materials: materials, injection: injection)
            crashReset(injection.killAfter, .journalPrepared)
        }
        try await continueReset(journal, materials: materials, day: day, injection: injection)
        return target
    }

    private func prepareJournal(operationID: UUID, target: CycleID) async throws -> ResetJournalPayload {
        let current = try requireObject(CycleRecord.self, identity: CycleResetObjects.currentCycle,
                                        failure: .missingCurrentCycle)
        let preferences = try requireObject(Preferences.self, identity: CycleResetObjects.preferences,
                                            failure: .missingPreferences)
        let collected = try collectShards(cycleID: current.cycleID)
        let summary = try CycleSummaryReducer.reduce(cycleID: current.cycleID,
                                                    shortcuts: collected.shortcuts,
                                                    bareKeys: collected.bareKeys)
        return ResetJournalPayload(
            operationID: operationID, oldCycleID: current.cycleID, newCycleID: target,
            newCycleIndex: current.index.value + 1, expectedCollecting: preferences.expectedCollecting,
            summary: summary, retainedHashes: try retainedHashes(excluding: current.cycleID),
            phase: .prepared)
    }

    private func continueReset(
        _ journal: ResetJournalPayload, materials: [UInt32: Data],
        day: LocalDay, injection: CycleResetInjection
    ) async throws {
        try verifyRetained(journal)
        var advanced = journal
        if advanced.phase == .prepared {
            try await ensureSummary(advanced, injection: injection)
            advanced = advanced.advancing(to: .summaryWritten)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .summaryWritten)
        }
        if advanced.phase == .summaryWritten {
            try await deleteDetails(oldCycle: advanced.oldCycleID, injection: injection)
            advanced = advanced.advancing(to: .detailsRemoved)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .detailsRemoved)
        }
        if advanced.phase == .detailsRemoved {
            try await commitNewCycle(advanced, day: day, injection: injection)
            advanced = advanced.advancing(to: .cycleCommitted)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .cycleCommitted)
        }
        try verifyRetained(advanced)
        do {
            try cycleJournals.clearAll(knownVersions: Set(materials.keys), materials: materials,
                                       injection: injection.journalClear)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    private func ensureSummary(_ journal: ResetJournalPayload, injection: CycleResetInjection) async throws {
        let identity = CycleResetObjects.summary(journal.oldCycleID)
        if let entry = try opened().entry(for: identity) {
            guard try decodeStrict(CycleSummary.self, openPayload(entry)) == journal.summary else {
                throw ObjectStoreError.reset(.retainedObjectsChanged)
            }
            return
        }
        _ = try await put(identity: identity, payload: try encodeJSON(journal.summary),
                          injection: injection.summaryWrite)
    }

    private func deleteDetails(oldCycle: CycleID, injection: CycleResetInjection) async throws {
        for entry in try opened().entries where entry.identity.objectType == CanonicalLogicalIdentity.shardObjectType {
            let triple = try entry.identity.shardComponents()
            guard triple.cycleID == oldCycle.rawValue else { throw ObjectStoreError.reset(.shardCycleMismatch) }
            try await removePresent(entry.identity, injection: injection.detailDelete)
        }
    }

    private func commitNewCycle(_ journal: ResetJournalPayload, day: LocalDay,
                                injection: CycleResetInjection) async throws {
        let current = try? currentCycleRecord()
        if current?.cycleID != journal.newCycleID {
            let record = CycleRecord(cycleID: journal.newCycleID, index: try Count(journal.newCycleIndex),
                                     createdDay: day, closedDay: nil, isCurrent: true)
            _ = try await put(identity: CycleResetObjects.currentCycle, payload: try encodeJSON(record),
                              injection: injection.cycleWrite)
        }
        let preferences = try requireObject(Preferences.self, identity: CycleResetObjects.preferences,
                                            failure: .missingPreferences)
        if preferences.currentCycleID != journal.newCycleID {
            let updated = Preferences(
                currentCycleID: journal.newCycleID, expectedCollecting: journal.expectedCollecting,
                excludedBundleIDs: preferences.excludedBundleIDs,
                ignoredRecommendationKeys: preferences.ignoredRecommendationKeys,
                layout: preferences.layout, loginItemEnabled: preferences.loginItemEnabled,
                locale: preferences.locale, keyboardPoolConfirmed: preferences.keyboardPoolConfirmed)
            _ = try await put(identity: CycleResetObjects.preferences, payload: try encodeJSON(updated),
                              injection: injection.cycleWrite)
        }
    }
}
