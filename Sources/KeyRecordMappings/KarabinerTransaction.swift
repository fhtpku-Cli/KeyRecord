import Foundation
import CryptoKit
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore

public enum KarabinerWriteAuthority: Equatable, Sendable {
    case readOnly
    case temporaryConfiguration
    case qualifiedAdapter(version: String, testedProfiles: Set<String>)
}

public struct KarabinerRuntimeContext: Equatable, Sendable {
    public let version: String?
    public let authority: KarabinerWriteAuthority
    public let capabilities: BackendCapabilities?
    public let observations: [ChordBucket]?
    public let menu: MenuShortcutEvidence?
    public let generation: UInt64
    public init(version: String?, authority: KarabinerWriteAuthority = .readOnly,
                capabilities: BackendCapabilities? = nil, observations: [ChordBucket]? = nil, generation: UInt64 = 0,
                menu: MenuShortcutEvidence? = nil) {
        self.version = version; self.authority = authority; self.capabilities = capabilities
        self.observations = observations; self.generation = generation
        self.menu = menu
    }
    public func requireWrite(profile: String) throws {
        guard let capabilities, capabilities.backend == .karabiner else { throw KarabinerMappingError.readOnlyVersion }
        switch authority {
        case .readOnly: throw KarabinerMappingError.readOnlyVersion
        case .temporaryConfiguration: break
        case .qualifiedAdapter(let supported, let profiles):
            let parts = supported.split(separator: ".", omittingEmptySubsequences: false)
            guard version == supported, parts.count == 3,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }),
                  profiles.contains(profile) else { throw KarabinerMappingError.readOnlyVersion }
        }
    }
}

public protocol KarabinerConfigurationPort: Sendable {
    func context() throws -> KarabinerRuntimeContext
    func read() throws -> Data
    func replace(expected: Data, with bytes: Data, context: KarabinerRuntimeContext) throws
}

public enum KarabinerMappingState: String, Codable, CaseIterable, Sendable {
    case draft, written, pendingVerification, verified, failed, externallyChanged, rolledBack, disabled, unmanaged
}

public enum KarabinerOperationKind: String, Codable, Sendable { case apply, disable, restore, rollback, remove, behaviorTest }

public struct KarabinerBackup: Codable, Equatable, Sendable {
    public let id: UUID
    public let before: Data
    public let expected: Data
    public let drafts: [KarabinerMappingDraft]
    public let previousDesired: [KarabinerMappingDraft]
    public let previousDisabled: Bool
    public let previousProfile: String?
    public let destination: KarabinerManagement
}

public struct KarabinerManagement: Codable, Equatable, Sendable {
    public let desired: [KarabinerMappingDraft]
    public let disabled: Bool
    public let profile: String?
}

public struct KarabinerBatch: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let profile: String
    public let kind: KarabinerOperationKind
    public let beforeSHA256: String
    public let expectedSHA256: String
    public let backupID: UUID
    public let created: Date
    public var state: KarabinerMappingState
    public var verifiedAt: Date?
    public var verificationSource: String?
}

public struct KarabinerLedger: Codable, Equatable, Sendable {
    public var batches: [KarabinerBatch] = []
    public var pending: UUID?
    public var managedProfile: String?
    public var desired: [KarabinerMappingDraft] = []
    public var disabled = false
    public var acceptedSHA256: String?
    public var cleanupBackups: [UUID] = []
    public init() {}
    public var mappingRecords: [KarabinerMappingRecord] {
        desired.map { KarabinerMappingRecord(draft: $0, state: batches.last?.state ?? .draft,
            verificationSource: batches.last?.verificationSource, verifiedAt: batches.last?.verifiedAt) }
    }
}

public struct KarabinerMappingRecord: Equatable, Sendable, Identifiable {
    public let draft: KarabinerMappingDraft
    public let state: KarabinerMappingState
    public let verificationSource: String?
    public let verifiedAt: Date?
    public var id: UUID { draft.id }
}

public protocol KarabinerTransactionStore: Sendable {
    func load() async throws -> KarabinerLedger
    func save(_ ledger: KarabinerLedger) async throws
    func putBackup(_ backup: KarabinerBackup) async throws
    func backup(_ id: UUID) async throws -> KarabinerBackup
    func removeBackup(_ id: UUID) async throws
    func discardUnreferencedBackups(retaining ids: Set<UUID>) async throws
}

public actor EncryptedKarabinerTransactionStore: KarabinerTransactionStore {
    private let store: ObjectStore
    private let identity: CanonicalLogicalIdentity
    private let backupPrefix: String
    public init(store: ObjectStore, namespace: UUID) throws {
        self.store = store
        backupPrefix = namespace.uuidString + "/"
        identity = try CanonicalLogicalIdentity(objectType: "com.keyrecord.mapping-journal", schemaVersion: 1, logicalIDText: namespace.uuidString)
    }
    public func load() async throws -> KarabinerLedger {
        guard try await store.entries().contains(where: { $0.identity == identity }) else { return KarabinerLedger() }
        return try JSONDecoder().decode(KarabinerLedger.self, from: await store.read(identity))
    }
    public func save(_ ledger: KarabinerLedger) async throws { _ = try await store.put(identity: identity, payload: JSONEncoder().encode(ledger)) }
    public func putBackup(_ backup: KarabinerBackup) async throws {
        _ = try await store.put(identity: backupIdentity(backup.id), payload: JSONEncoder().encode(backup))
    }
    public func backup(_ id: UUID) async throws -> KarabinerBackup {
        try JSONDecoder().decode(KarabinerBackup.self, from: await store.read(backupIdentity(id)))
    }
    public func removeBackup(_ id: UUID) async throws {
        let identity = try backupIdentity(id)
        if try await store.entries().contains(where: { $0.identity == identity }) { try await store.delete(identity) }
    }
    public func discardUnreferencedBackups(retaining ids: Set<UUID>) async throws {
        for entry in try await store.entries() where entry.identity.objectType == "com.keyrecord.mapping-backup" {
            guard let logicalID = entry.identity.logicalIDText, logicalID.hasPrefix(backupPrefix),
                  let id = UUID(uuidString: String(logicalID.dropFirst(backupPrefix.count))) else { continue }
            if !ids.contains(id) { try await store.delete(entry.identity) }
        }
    }
    private func backupIdentity(_ id: UUID) throws -> CanonicalLogicalIdentity {
        try CanonicalLogicalIdentity(objectType: "com.keyrecord.mapping-backup", schemaVersion: 1, logicalIDText: backupPrefix + id.uuidString)
    }
}

public enum KarabinerRecoveryClassification: Equatable, Sendable { case ourWrite, noWrite, externalChange }
public enum KarabinerExternalChoice: Sendable { case adopt, reapply, stopManaging }

public struct KarabinerPreparedOperation: Equatable, Sendable {
    public let plan: KarabinerPlan
    public let context: KarabinerRuntimeContext
    public let reports: [CandidateConflictReport]
    public var hasChainedMapping: Bool { reports.contains { CandidateConflictDetector.hasMappingChain($0.check.input) } }
    public var hasBlockingConflict: Bool {
        hasChainedMapping || reports.contains { report in
            report.findings.contains { $0.severity == .blocking } || {
                if case .unsupported = report.readiness { return true }; return false
            }()
        }
    }
    public var requiresRiskConfirmation: Bool {
        reports.contains { $0.findings.contains { $0.severity == .warning } }
            || plan.drafts.contains { ManualCandidateDraft.needsRiskConfirmation($0.trigger) }
    }
}

public actor KarabinerTransactionCoordinator {
    private let configuration: any KarabinerConfigurationPort
    private let store: any KarabinerTransactionStore
    private var busy = false
    private var activeBehaviorTest: UUID?
    public init(configuration: any KarabinerConfigurationPort, store: any KarabinerTransactionStore) {
        self.configuration = configuration; self.store = store
    }
    public nonisolated func currentContext() throws -> KarabinerRuntimeContext { try configuration.context() }
    public func prepare(profile: String, drafts: [KarabinerMappingDraft]) throws -> KarabinerPreparedOperation {
        try prepare(base: configuration.read(), profile: profile, drafts: drafts, context: configuration.context())
    }
    private func prepare(base: Data, profile: String, drafts: [KarabinerMappingDraft], context: KarabinerRuntimeContext) throws -> KarabinerPreparedOperation {
        let plan = try KarabinerProfilePlanner.plan(base, profile: profile, drafts: drafts)
        let capabilities = context.capabilities ?? BackendCapabilityCatalog.reference(.karabiner)
        let reports = drafts.map { draft in
            let rules = plan.userEvidence.rules + drafts.filter { $0.id != draft.id }.map(\.backendRule)
            let evidence = BackendRuleEvidence(backend: .karabiner, profile: profile, rules: rules,
                unsupportedRuleCount: plan.userEvidence.unsupportedRuleCount,
                origin: context.authority == .readOnly ? .selectedCopy : .currentAdapter, backendVersion: context.version)
            return CandidateConflictDetector.evaluate(CandidateCheckInput(source: draft.output, trigger: draft.trigger,
                scope: draft.scope.recommendation, backend: context.authority == .readOnly ? .disconnected(.karabiner) : capabilities.map(BackendConnection.connected) ?? .disconnected(.karabiner),
                conflictEvidence: CandidateConflictEvidence(observations: context.observations, backendRules: evidence,
                    profile: profile, devices: draft.devices.map { Set($0.map(\.identity)) }, menu: context.menu)))
        }
        return KarabinerPreparedOperation(plan: plan, context: context, reports: reports)
    }
    public func ledger() async throws -> KarabinerLedger { try await store.load() }

    public func apply(_ prepared: KarabinerPreparedOperation, riskConfirmed: Bool = false) async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil else { throw KarabinerMappingError.busy }
        guard ledger.managedProfile == nil || ledger.managedProfile == prepared.plan.diff.profile else { throw KarabinerMappingError.invalidDraft }
        if let accepted = ledger.acceptedSHA256, digest(try configuration.read()) != accepted { throw KarabinerMappingError.externalChange }
        try await commit(prepared, kind: .apply, riskConfirmed: riskConfirmed, ledger: &ledger)
        return ledger
    }
    private func begin(allowBehaviorTest: Bool = false) throws {
        guard !busy, allowBehaviorTest || activeBehaviorTest == nil else { throw KarabinerMappingError.busy }
        busy = true
    }

    public func prepareBehaviorTest(profile: String, drafts: [KarabinerMappingDraft]) throws -> KarabinerPreparedOperation {
        guard !drafts.isEmpty, drafts.allSatisfy({ if case .application = $0.scope { return true }; return false }) else {
            throw KarabinerMappingError.invalidDraft
        }
        return try prepare(profile: profile, drafts: drafts.map { draft in
            var temporary = draft; temporary.temporary = true; return temporary
        })
    }

    public func startBehaviorTest(_ prepared: KarabinerPreparedOperation, riskConfirmed: Bool = false) async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        guard ledger.pending == nil, !ledger.desired.contains(where: \.temporary),
              ledger.managedProfile == nil || ledger.managedProfile == prepared.plan.diff.profile,
              !prepared.plan.drafts.isEmpty,
              prepared.plan.drafts.allSatisfy({ draft in
                  if case .application = draft.scope { return draft.temporary }; return false
              }) else { throw KarabinerMappingError.invalidDraft }
        if let accepted = ledger.acceptedSHA256, digest(try configuration.read()) != accepted { throw KarabinerMappingError.externalChange }
        try await commit(prepared, kind: .behaviorTest, riskConfirmed: riskConfirmed, ledger: &ledger)
        guard ledger.batches.last?.state == .pendingVerification, ledger.pending == nil else { throw KarabinerMappingError.unavailable }
        activeBehaviorTest = ledger.batches.last?.id
        return ledger
    }

    public func endBehaviorTest() async throws -> KarabinerLedger {
        try begin(allowBehaviorTest: true); defer { busy = false }
        activeBehaviorTest = nil
        var ledger = try await store.load()
        try await finishCurrent(ledger: &ledger)
        try await cleanBehaviorTest(ledger: &ledger)
        return ledger
    }

    private func cleanBehaviorTest(ledger: inout KarabinerLedger) async throws {
        guard ledger.desired.contains(where: \.temporary),
              let batch = behaviorTestBatch(in: ledger) else { return }
        if Self.classify(current: try configuration.read(), batch: batch) == .noWrite {
            let backup = try await store.backup(batch.backupID)
            guard digest(backup.before) == batch.beforeSHA256 else { throw KarabinerMappingError.unavailable }
            ledger.desired = backup.previousDesired; ledger.disabled = backup.previousDisabled
            ledger.managedProfile = backup.previousProfile; ledger.acceptedSHA256 = batch.beforeSHA256
            if !ledger.batches.isEmpty {
                ledger.batches[ledger.batches.count - 1].state = .rolledBack
                ledger.batches[ledger.batches.count - 1].verificationSource = nil
                ledger.batches[ledger.batches.count - 1].verifiedAt = nil
            }
            try await store.save(ledger)
            return
        }
        try await rollback(batch: batch, ledger: &ledger)
        guard ledger.pending == nil, !ledger.desired.contains(where: \.temporary) else { throw KarabinerMappingError.unavailable }
    }
    private func requireNoBehaviorCleanup(_ ledger: KarabinerLedger) throws {
        if ledger.desired.contains(where: \.temporary), behaviorTestBatch(in: ledger) != nil {
            throw KarabinerMappingError.busy
        }
    }
    private func behaviorTestBatch(in ledger: KarabinerLedger) -> KarabinerBatch? {
        guard let batch = ledger.batches.last(where: { $0.kind != .rollback }), batch.kind == .behaviorTest else { return nil }
        return batch
    }

    private func commit(_ prepared: KarabinerPreparedOperation, kind: KarabinerOperationKind,
                        riskConfirmed: Bool, destination: KarabinerManagement? = nil, ledger: inout KarabinerLedger) async throws {
        let profile = prepared.plan.diff.profile
        try prepared.context.requireWrite(profile: profile)
        guard configurationContextMatches(prepared), try configuration.read() == prepared.plan.base else { throw KarabinerMappingError.externalChange }
        let fresh = try prepare(base: prepared.plan.base, profile: profile, drafts: prepared.plan.drafts, context: configuration.context())
        guard fresh == prepared else { throw KarabinerMappingError.externalChange }
        guard !fresh.hasBlockingConflict else { throw KarabinerMappingError.conflict }
        guard riskConfirmed || !fresh.requiresRiskConfirmation else { throw KarabinerMappingError.riskConfirmationRequired }
        try await write(base: prepared.plan.base, expected: prepared.plan.bytes, drafts: prepared.plan.drafts,
            profile: profile, context: prepared.context, kind: kind, restoring: destination, ledger: &ledger)
    }
    private func configurationContextMatches(_ prepared: KarabinerPreparedOperation) -> Bool {
        (try? configuration.context()) == prepared.context
    }
    private func write(base: Data, expected: Data, drafts: [KarabinerMappingDraft], profile: String,
                       context: KarabinerRuntimeContext, kind: KarabinerOperationKind,
                       restoring: KarabinerManagement? = nil, ledger: inout KarabinerLedger) async throws {
        let id = UUID()
        let destination: KarabinerManagement
        if let restoring { destination = restoring }
        else { switch kind {
        case .apply, .restore, .behaviorTest: destination = KarabinerManagement(desired: drafts, disabled: false, profile: profile)
        case .disable: destination = KarabinerManagement(desired: ledger.desired, disabled: true, profile: profile)
        case .remove: destination = KarabinerManagement(desired: [], disabled: false, profile: nil)
        case .rollback:
            throw KarabinerMappingError.unavailable
        } }
        let backup = KarabinerBackup(id: id, before: base, expected: expected, drafts: drafts,
            previousDesired: ledger.desired, previousDisabled: ledger.disabled, previousProfile: ledger.managedProfile,
            destination: destination)
        try await store.putBackup(backup)
        let batch = KarabinerBatch(id: id, profile: profile, kind: kind, beforeSHA256: digest(base),
            expectedSHA256: digest(expected), backupID: id, created: Date(), state: .written)
        ledger.batches.append(batch); ledger.pending = id
        try await store.save(ledger)
        do {
            try configuration.replace(expected: base, with: expected, context: context)
            if try configuration.read() != expected { return try await finishCurrent(ledger: &ledger) }
            try await finishCurrent(ledger: &ledger)
        } catch {
            try await finishCurrent(ledger: &ledger)
            throw error
        }
    }
    public static func classify(current: Data, batch: KarabinerBatch) -> KarabinerRecoveryClassification {
        if digest(current) == batch.expectedSHA256 { return .ourWrite }
        if digest(current) == batch.beforeSHA256 { return .noWrite }
        return .externalChange
    }
    private func finishCurrent(ledger: inout KarabinerLedger) async throws {
        guard let id = ledger.pending, let index = ledger.batches.firstIndex(where: { $0.id == id }) else { return }
        let batch = ledger.batches[index]
        switch Self.classify(current: try configuration.read(), batch: batch) {
        case .ourWrite:
            let backup = try await store.backup(batch.backupID)
            guard digest(backup.expected) == batch.expectedSHA256, digest(backup.before) == batch.beforeSHA256 else { throw KarabinerMappingError.unavailable }
            ledger.batches[index].state = batch.kind == .rollback ? .rolledBack : batch.kind == .disable ? .disabled : batch.kind == .remove ? .unmanaged : .pendingVerification
            ledger.acceptedSHA256 = batch.expectedSHA256
            ledger.managedProfile = backup.destination.profile
            ledger.desired = backup.destination.desired
            ledger.disabled = backup.destination.disabled
        case .noWrite: ledger.batches[index].state = .failed
        case .externalChange:
            ledger.batches[index].state = .externallyChanged
            ledger.managedProfile = batch.profile
            if batch.kind == .apply || batch.kind == .behaviorTest { ledger.desired = try await store.backup(batch.backupID).drafts }
        }
        ledger.pending = nil
        try await store.save(ledger)
        try await trim(ledger: &ledger)
    }
    private func trim(ledger: inout KarabinerLedger) async throws {
        while ledger.batches.count > 10 {
            let testID = ledger.desired.contains(where: \.temporary)
                ? behaviorTestBatch(in: ledger)?.id : nil
            let index = ledger.batches.firstIndex(where: { $0.id != testID }) ?? 0
            let oldest = ledger.batches.remove(at: index)
            ledger.cleanupBackups.append(oldest.backupID)
            try await store.save(ledger)
        }
        while let id = ledger.cleanupBackups.first {
            try await store.removeBackup(id)
            ledger.cleanupBackups.removeFirst()
            try await store.save(ledger)
        }
    }
    public func reconcile(rollbackRequested: Bool = false) async throws -> KarabinerLedger {
        try begin(allowBehaviorTest: true); defer { busy = false }
        var ledger = try await store.load()
        try await trim(ledger: &ledger)
        try await store.discardUnreferencedBackups(retaining: Set(ledger.batches.map(\.backupID)))
        if let id = ledger.pending, let batch = ledger.batches.first(where: { $0.id == id }) {
            if rollbackRequested, Self.classify(current: try configuration.read(), batch: batch) == .ourWrite {
                try await rollback(batch: batch, ledger: &ledger)
            } else { try await finishCurrent(ledger: &ledger) }
        }
        if let accepted = ledger.acceptedSHA256, digest(try configuration.read()) != accepted {
            if !ledger.batches.isEmpty {
                ledger.batches[ledger.batches.count - 1].state = .externallyChanged
                ledger.batches[ledger.batches.count - 1].verifiedAt = nil
                ledger.batches[ledger.batches.count - 1].verificationSource = nil
            }
            try await store.save(ledger)
        }
        if ledger.batches.last?.state == .externallyChanged { activeBehaviorTest = nil }
        if activeBehaviorTest != nil { return ledger }
        if ledger.desired.contains(where: \.temporary), behaviorTestBatch(in: ledger) != nil {
            try await cleanBehaviorTest(ledger: &ledger)
        } else if let profile = ledger.managedProfile, ledger.desired.contains(where: \.temporary), ledger.batches.last?.state != .externallyChanged {
            let permanent = ledger.desired.filter { !$0.temporary }
            let prepared = try prepare(profile: profile, drafts: ledger.disabled ? [] : permanent)
            try await commit(prepared, kind: ledger.disabled ? .disable : .apply, riskConfirmed: true,
                destination: KarabinerManagement(desired: permanent, disabled: ledger.disabled, profile: profile), ledger: &ledger)
        }
        return ledger
    }
    public func verifyConfiguration() async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil, let expected = ledger.acceptedSHA256, !ledger.batches.isEmpty else { throw KarabinerMappingError.unavailable }
        let index = ledger.batches.count - 1
        if digest(try configuration.read()) == expected {
            if ledger.batches[index].state == .pendingVerification {
                ledger.batches[index].state = .verified
                ledger.batches[index].verificationSource = "configurationReadback"
                ledger.batches[index].verifiedAt = Date()
            }
        } else {
            ledger.batches[index].state = .externallyChanged
            ledger.batches[index].verifiedAt = nil
            ledger.batches[index].verificationSource = nil
        }
        try await store.save(ledger)
        return ledger
    }
    public func setDisabled(_ disabled: Bool, confirmation: KarabinerPreparedOperation? = nil) async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil, let profile = ledger.managedProfile,
              ledger.acceptedSHA256 == digest(try configuration.read()) else { throw KarabinerMappingError.externalChange }
        let desired = ledger.desired
        let prepared = try prepare(profile: profile, drafts: disabled ? [] : desired)
        try await commit(prepared, kind: disabled ? .disable : .restore,
            riskConfirmed: disabled || confirmation == prepared, ledger: &ledger)
        return ledger
    }
    public func rollbackLatest() async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil, let batch = ledger.batches.last else { throw KarabinerMappingError.unavailable }
        let backup = try await store.backup(batch.backupID)
        guard !backup.previousDesired.contains(where: \.temporary) else {
            throw KarabinerMappingError.unavailable
        }
        try await rollback(batch: batch, ledger: &ledger)
        return ledger
    }
    private func rollback(batch: KarabinerBatch, ledger: inout KarabinerLedger) async throws {
        let current = try configuration.read()
        switch Self.classify(current: current, batch: batch) {
        case .noWrite:
            ledger.batches[ledger.batches.count - 1].state = .failed; ledger.pending = nil; try await store.save(ledger)
        case .externalChange: throw KarabinerMappingError.externalChange
        case .ourWrite:
            let backup = try await store.backup(batch.backupID)
            guard digest(backup.before) == batch.beforeSHA256,
                  !backup.previousDesired.contains(where: \.temporary) else { throw KarabinerMappingError.unavailable }
            let context = try configuration.context(); try context.requireWrite(profile: batch.profile)
            ledger.pending = nil
            try await write(base: current, expected: backup.before, drafts: backup.previousDesired, profile: batch.profile,
                context: context, kind: .rollback,
                restoring: KarabinerManagement(desired: backup.previousDesired, disabled: backup.previousDisabled, profile: backup.previousProfile), ledger: &ledger)
        }
    }
    public func resolveExternal(_ choice: KarabinerExternalChoice, confirmation: KarabinerPreparedOperation? = nil) async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil, let profile = ledger.managedProfile else { throw KarabinerMappingError.unavailable }
        let current = try configuration.read()
        switch choice {
        case .adopt:
            let temporaryIDs = Set(ledger.desired.filter(\.temporary).map(\.id))
            ledger.desired = try KarabinerProfilePlanner.adoptedDrafts(current, profile: profile).map { draft in
                var adopted = draft
                adopted.temporary = temporaryIDs.contains(draft.id)
                return adopted
            }
            guard ledger.desired.count <= 256, Set(ledger.desired.map(\.id)).count == ledger.desired.count else { throw KarabinerMappingError.invalidDraft }
            ledger.acceptedSHA256 = digest(current)
            ledger.disabled = ledger.desired.isEmpty
            if !ledger.batches.isEmpty {
                ledger.batches[ledger.batches.count - 1].state = .pendingVerification
                ledger.batches[ledger.batches.count - 1].verifiedAt = nil
                ledger.batches[ledger.batches.count - 1].verificationSource = nil
            }
            try await store.save(ledger)
        case .stopManaging:
            ledger.desired = []; ledger.managedProfile = nil; ledger.acceptedSHA256 = nil; ledger.disabled = false
            if !ledger.batches.isEmpty { ledger.batches[ledger.batches.count - 1].state = .unmanaged }
            try await store.save(ledger)
        case .reapply:
            let prepared = try prepare(base: current, profile: profile, drafts: ledger.disabled ? [] : ledger.desired, context: configuration.context())
            try await commit(prepared, kind: ledger.disabled ? .disable : .apply,
                riskConfirmed: confirmation == prepared, ledger: &ledger)
        }
        return ledger
    }
    public func prepareRestore() async throws -> KarabinerPreparedOperation {
        let ledger = try await store.load()
        guard let profile = ledger.managedProfile else { throw KarabinerMappingError.unavailable }
        return try prepare(profile: profile, drafts: ledger.desired)
    }
    public func removeManagedRules() async throws -> KarabinerLedger {
        try begin(); defer { busy = false }
        var ledger = try await store.load()
        try requireNoBehaviorCleanup(ledger)
        guard ledger.pending == nil, let profile = ledger.managedProfile,
              ledger.acceptedSHA256 == digest(try configuration.read()) else { throw KarabinerMappingError.externalChange }
        let current = try configuration.read()
        let plan = try KarabinerProfilePlanner.plan(current, profile: profile, drafts: [], remove: true)
        let context = try configuration.context(); try context.requireWrite(profile: profile)
        try await write(base: current, expected: plan.bytes, drafts: [], profile: profile,
            context: context, kind: .remove, ledger: &ledger)
        return ledger
    }
    static func fileDigest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}

private func digest(_ bytes: Data) -> String { KarabinerTransactionCoordinator.fileDigest(bytes) }
