import Foundation
import KeyRecordCore

extension ObjectStore {
    /// Contract 9 ordered idempotent transaction. The store lease serializes every reset
    /// against key rotation; a duplicated operation ID converges to the same new cycle.
    /// The operation a durable journal already owns, or nil when no reset is pending.
    /// Throws when a journal file exists but cannot be authenticated; callers must not
    /// replace it with a new operation or report the reset finished.
    public func pendingResetOperationID() async throws -> UUID? {
        let sessionToken = protectedSessionToken
        let journals = try await loadPendingResetJournals()
        try requireProtectedSession(sessionToken)
        return journals.last?.payload.operationID
    }

    /// Continues the journal's own operation when one is on disk. Returns false when there
    /// is nothing to continue. A failure leaves the journal in place.
    public func continueUnfinishedReset(day: LocalDay) async throws -> Bool {
        guard bootstrapState() == .opened else { return false }
        let sessionToken = protectedSessionToken
        let pending = try await pendingResetOperationID()
        try requireProtectedSession(sessionToken)
        guard let operation = pending else { return false }
        _ = try await resetCycle(operationID: operation, day: day)
        try requireProtectedSession(sessionToken)
        return true
    }

    private func loadPendingResetJournals() async throws -> [LoadedResetJournal] {
        _ = try opened()
        let sessionToken = protectedSessionToken
        let versions = try await keySource.namespaceKeyVersions()
        try requireProtectedSession(sessionToken)
        let raw = Set(versions.map(\.rawValue))
        var materials: [UInt32: Data] = [:]
        for version in raw.sorted() {
            materials[version] = try await material(version, versions: versions)
            try requireProtectedSession(sessionToken)
        }
        return try cycleJournals.load(knownVersions: raw, materials: materials)
    }

    public func resetCycle(operationID: UUID, day: LocalDay,
                           injection provided: CycleResetInjection? = nil) async throws -> CycleID {
        _ = try opened()
        let sessionToken = protectedSessionToken
        let leaseID = try beginLease()
        defer { endLease(leaseID) }
        let injection = provided ?? configuredResetInjection
        let target = CycleResetIdentifiers.newCycleID(operationID: operationID)

        let keyVersions = Set((try await keySource.namespaceKeyVersions()).map(\.rawValue))
        try requireProtectedSession(sessionToken)
        var materials: [UInt32: Data] = [:]
        for raw in keyVersions.sorted() {
            materials[raw] = try await material(raw, versions: nil)
            try requireProtectedSession(sessionToken)
        }
        let pending = try cycleJournals.load(knownVersions: keyVersions, materials: materials)

        let journal: ResetJournalPayload
        if let existing = pending.last {
            guard existing.payload.operationID == operationID else {
                throw ObjectStoreError.reset(.conflictingOperation)
            }
            journal = existing.payload
        } else {
            if let current = try? currentCycleRecord(), current.cycleID == target { return target }
            journal = try await prepareJournal(operationID: operationID, target: target,
                                               sessionToken: sessionToken)
            try requireProtectedSession(sessionToken)
            try persistJournal(journal, materials: materials, injection: injection)
            crashReset(injection.killAfter, .journalPrepared)
        }
        try await continueReset(journal, materials: materials, day: day,
                                injection: injection, sessionToken: sessionToken)
        try requireProtectedSession(sessionToken)
        return target
    }

    private func prepareJournal(operationID: UUID, target: CycleID,
                                sessionToken: UUID) async throws -> ResetJournalPayload {
        try requireProtectedSession(sessionToken)
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
        day: LocalDay, injection: CycleResetInjection, sessionToken: UUID
    ) async throws {
        try requireProtectedSession(sessionToken)
        try verifyRetained(journal)
        var advanced = journal
        if advanced.phase == .prepared {
            try await ensureSummary(advanced, injection: injection, sessionToken: sessionToken)
            try requireProtectedSession(sessionToken)
            advanced = advanced.advancing(to: .summaryWritten)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .summaryWritten)
        }
        if advanced.phase == .summaryWritten {
            try await deleteDetails(oldCycle: advanced.oldCycleID, injection: injection,
                                    sessionToken: sessionToken)
            try requireProtectedSession(sessionToken)
            advanced = advanced.advancing(to: .detailsRemoved)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .detailsRemoved)
        }
        if advanced.phase == .detailsRemoved {
            try await commitNewCycle(advanced, day: day, injection: injection,
                                     sessionToken: sessionToken)
            try requireProtectedSession(sessionToken)
            advanced = advanced.advancing(to: .cycleCommitted)
            try persistJournal(advanced, materials: materials, injection: injection)
            crashReset(injection.killAfter, .cycleCommitted)
        }
        try requireProtectedSession(sessionToken)
        try verifyRetained(advanced)
        do {
            try cycleJournals.clearAll(knownVersions: Set(materials.keys), materials: materials,
                                       injection: injection.journalClear)
        } catch let error as FileSystemError {
            throw ObjectStoreError.filesystem(error)
        }
    }

    private func ensureSummary(_ journal: ResetJournalPayload, injection: CycleResetInjection,
                               sessionToken: UUID) async throws {
        try requireProtectedSession(sessionToken)
        let identity = CycleResetObjects.summary(journal.oldCycleID)
        if let entry = try opened().entry(for: identity) {
            guard try decodeStrict(CycleSummary.self, openPayload(entry)) == journal.summary else {
                throw ObjectStoreError.reset(.retainedObjectsChanged)
            }
            return
        }
        _ = try await put(identity: identity, payload: try encodeJSON(journal.summary),
                          injection: injection.summaryWrite)
        try requireProtectedSession(sessionToken)
    }

    private func deleteDetails(oldCycle: CycleID, injection: CycleResetInjection,
                               sessionToken: UUID) async throws {
        try requireProtectedSession(sessionToken)
        try await removePresent(AggregateDayOrder.identity(oldCycle), injection: injection.detailDelete)
        try requireProtectedSession(sessionToken)
        for entry in try opened().entries where entry.identity.objectType == CanonicalLogicalIdentity.shardObjectType {
            try requireProtectedSession(sessionToken)
            let triple = try entry.identity.shardComponents()
            guard triple.cycleID == oldCycle.rawValue else { throw ObjectStoreError.reset(.shardCycleMismatch) }
            try await removePresent(entry.identity, injection: injection.detailDelete)
            try requireProtectedSession(sessionToken)
        }
    }

    private func commitNewCycle(_ journal: ResetJournalPayload, day: LocalDay,
                                injection: CycleResetInjection, sessionToken: UUID) async throws {
        try requireProtectedSession(sessionToken)
        let current = try? currentCycleRecord()
        if current?.cycleID != journal.newCycleID {
            let record = CycleRecord(cycleID: journal.newCycleID, index: try Count(journal.newCycleIndex),
                                     createdDay: day, closedDay: nil, isCurrent: true)
            _ = try await put(identity: CycleResetObjects.currentCycle, payload: try encodeJSON(record),
                              injection: injection.cycleWrite)
            try requireProtectedSession(sessionToken)
        }
        try requireProtectedSession(sessionToken)
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
            try requireProtectedSession(sessionToken)
        }
    }
}
