import XCTest
import Foundation
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore
@testable import KeyRecordMappings

let mappingBase = Data(#"{"global":{"opaque":"retain me"},"profiles":[{"name":"Other","complex_modifications":{"rules":[]}},{"name":"Work","selected":true,"complex_modifications":{"parameters":{"opaque":13},"rules":[ {"description":"User A","manipulators":[{"type":"basic","from":{"key_code":"a"},"to":[{"key_code":"b"}]}]} ]}}]}"#.utf8)
let mappingModifiers = ModifierSet(command: .none, option: .none, control: .none, shift: .none, fn: .none)
func mappingChord(_ value: Int) throws -> Chord { Chord(keyCode: try KeyCode(value), modifiers: mappingModifiers) }
func mappingDraft(_ trigger: Int = 111, output: Int = 8, scope: MappingScope = .global,
                  devices: Set<MappingDevice>? = nil) throws -> KarabinerMappingDraft {
    KarabinerMappingDraft(name: "Synthetic mapping", profile: "Work", trigger: try mappingChord(trigger),
        output: try mappingChord(output), scope: scope, devices: devices)
}

final class MappingMemoryPort: KarabinerConfigurationPort, @unchecked Sendable {
    let mutex = NSLock()
    var bytes = mappingBase
    var runtime = KarabinerRuntimeContext(version: "fixture", authority: .temporaryConfiguration,
        capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: [])
    var writes = 0
    var mode = 0
    var readbackOnce: Data?
    func context() -> KarabinerRuntimeContext { mutex.withLock { runtime } }
    func read() -> Data {
        mutex.withLock {
            if let value = readbackOnce { readbackOnce = nil; return value }
            return bytes
        }
    }
    func replace(expected: Data, with proposed: Data, context: KarabinerRuntimeContext) throws {
        try mutex.withLock {
            guard bytes == expected, runtime == context else { throw KarabinerMappingError.externalChange }
            writes += 1
            if mode == 1 { throw KarabinerMappingError.unavailable }
            bytes = proposed
            if mode == 2 { bytes = mappingBase + Data(" ".utf8) }
            if mode == 3 { readbackOnce = mappingBase }
            if mode == 4 { throw KarabinerMappingError.unavailable }
        }
    }
    func external(_ data: Data) { mutex.withLock { bytes = data } }
    func setMode(_ mode: Int) { mutex.withLock { self.mode = mode } }
    func setRuntime(_ value: KarabinerRuntimeContext) { mutex.withLock { runtime = value } }
}

actor MappingMemoryStore: KarabinerTransactionStore {
    var value = KarabinerLedger()
    var backups: [UUID: KarabinerBackup] = [:]
    var failSave = false
    var saves = 0
    var failSaveNumber: Int?
    func load() -> KarabinerLedger { value }
    func save(_ ledger: KarabinerLedger) throws {
        saves += 1
        if failSave || saves == failSaveNumber { throw KarabinerMappingError.unavailable }; value = ledger
    }
    func putBackup(_ backup: KarabinerBackup) { backups[backup.id] = backup }
    func backup(_ id: UUID) throws -> KarabinerBackup {
        guard let backup = backups[id] else { throw KarabinerMappingError.unavailable }; return backup
    }
    func removeBackup(_ id: UUID) { backups[id] = nil }
    func discardUnreferencedBackups(retaining ids: Set<UUID>) { backups = backups.filter { ids.contains($0.key) } }
    func set(_ ledger: KarabinerLedger) { value = ledger }
    func failAtSave(_ number: Int?) { failSaveNumber = number }
}

final class KarabinerMappingTests: XCTestCase, @unchecked Sendable {
    func testBehaviorTestSurvivesRefreshAndRestoresDisabledPermanentConfiguration() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        let permanent = try mappingDraft()
        _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [permanent]))
        _ = try await coordinator.setDisabled(true)
        let before = port.read()
        let prepared = try await coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(109, scope: .application("com.example.Editor"))])
        let started = try await coordinator.startBehaviorTest(prepared)
        XCTAssertTrue(started.desired.allSatisfy(\.temporary))
        XCTAssertNotEqual(port.read(), before)
        let refreshed = try await coordinator.reconcile()
        XCTAssertEqual(refreshed.desired, started.desired)
        do { _ = try await coordinator.setDisabled(true); XCTFail("Active test must not be changed by management operations") }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .busy) }
        let ended = try await coordinator.endBehaviorTest()
        XCTAssertEqual(port.read(), before)
        XCTAssertEqual(ended.desired, [permanent]); XCTAssertTrue(ended.disabled)
        XCTAssertNil(ended.batches.last?.verificationSource)
        do { _ = try await coordinator.rollbackLatest(); XCTFail("Rollback must not resurrect temporary rules") }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .unavailable) }
    }

    func testBehaviorTestCrashReopenRestoresExactPretestBytes() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        _ = try await coordinator.startBehaviorTest(coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))]))
        let result = try await KarabinerTransactionCoordinator(configuration: port, store: store).reconcile()
        XCTAssertEqual(port.read(), mappingBase)
        XCTAssertNil(result.managedProfile); XCTAssertFalse(result.desired.contains(where: \.temporary))
    }

    func testAbandonedBehaviorTestBlocksOtherWritesAndRecognizesManualExactRestoration() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        _ = try await coordinator.startBehaviorTest(coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))]))
        let reopened = KarabinerTransactionCoordinator(configuration: port, store: store)
        do { _ = try await reopened.apply(reopened.prepare(profile: "Work", drafts: [mappingDraft()])); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .busy) }
        do { _ = try await reopened.resolveExternal(.stopManaging); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .busy) }
        port.external(mappingBase)
        let cleaned = try await reopened.endBehaviorTest()
        XCTAssertTrue(cleaned.desired.isEmpty); XCTAssertNil(cleaned.managedProfile)
        XCTAssertEqual(port.writes, 1)
    }

    func testBehaviorTestWriteAndJournalFailuresRecoverOnReopen() async throws {
        for failure in [1, 2, 4, 5] {
            let port = MappingMemoryPort(), store = MappingMemoryStore()
            let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
            if failure == 5 { await store.failAtSave(2) } else { port.setMode(failure) }
            do {
                _ = try await coordinator.startBehaviorTest(coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))]))
                XCTFail("Injected fault should not start a successful test")
            } catch {}
            port.setMode(0); await store.failAtSave(nil)
            if failure == 2 {
                let external = port.read()
                do { _ = try await coordinator.endBehaviorTest(); XCTFail() }
                catch { XCTAssertEqual(error as? KarabinerMappingError, .externalChange) }
                XCTAssertEqual(port.read(), external)
            } else {
                let result = try await KarabinerTransactionCoordinator(configuration: port, store: store).reconcile()
                XCTAssertEqual(port.read(), mappingBase)
                XCTAssertFalse(result.desired.contains(where: \.temporary))
            }
        }
    }

    func testBehaviorTestCleanupRetriesKeepOriginalBackupAndProtectExternalEdits() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        _ = try await coordinator.startBehaviorTest(coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))]))
        let during = port.read()
        port.external(during + Data(" ".utf8))
        do { _ = try await coordinator.endBehaviorTest(); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .externalChange) }
        XCTAssertEqual(port.read(), during + Data(" ".utf8))
        port.external(during); port.setMode(1)
        for _ in 0..<12 {
            do { _ = try await coordinator.endBehaviorTest(); XCTFail() } catch {}
        }
        port.setMode(0)
        _ = try await KarabinerTransactionCoordinator(configuration: port, store: store).reconcile()
        XCTAssertEqual(port.read(), mappingBase)
    }

    func testBehaviorTestRejectsGlobalReadOnlyStaleAndUnconfirmedRisk() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        do { _ = try await coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft()]); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .invalidDraft) }
        let risky = try await coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(8, output: 111, scope: .application("com.example.Editor"))])
        do { _ = try await coordinator.startBehaviorTest(risky); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .riskConfirmationRequired) }
        port.setRuntime(KarabinerRuntimeContext(version: nil))
        let readOnly = try await coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))])
        do { _ = try await coordinator.startBehaviorTest(readOnly); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .readOnlyVersion) }
        XCTAssertEqual(port.writes, 0)
        port.setRuntime(KarabinerRuntimeContext(version: "fixture", authority: .temporaryConfiguration,
            capabilities: BackendCapabilityCatalog.reference(.karabiner), observations: []))
        let stale = try await coordinator.prepareBehaviorTest(profile: "Work", drafts: [mappingDraft(scope: .application("com.example.Editor"))])
        port.external(mappingBase + Data(" ".utf8))
        do { _ = try await coordinator.startBehaviorTest(stale); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .externalChange) }
        XCTAssertEqual(port.writes, 0)
    }
    func testJournalFailureBeforeWriteAndAfterWriteRecovers() async throws {
        for number in [1, 2] {
            let port = MappingMemoryPort(), store = MappingMemoryStore()
            await store.failAtSave(number)
            let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
            do { _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft()])) } catch {}
            XCTAssertEqual(port.writes, number == 1 ? 0 : 1)
            await store.failAtSave(nil)
            let result = try await KarabinerTransactionCoordinator(configuration: port, store: store).reconcile()
            XCTAssertNil(result.pending)
            if number == 2 { XCTAssertEqual(result.batches.last?.state, .pendingVerification) }
            let retained = await store.backups.count
            XCTAssertEqual(retained, number == 1 ? 0 : 1)
        }
    }
    func testTemporaryRulesCleanAfterReopenAndRollbackRestoresManagement() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        var temporary = try mappingDraft(109); temporary.temporary = true
        _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft(), temporary]))
        port.external(port.read() + Data(" ".utf8))
        _ = try await coordinator.resolveExternal(.adopt)
        let adopted = try await coordinator.ledger()
        XCTAssertTrue(adopted.desired.contains(where: \.temporary))
        _ = try await coordinator.setDisabled(true)
        let cleaned = try await coordinator.reconcile()
        XCTAssertTrue(cleaned.disabled)
        XCTAssertEqual(cleaned.desired.count, 1)
        XCTAssertFalse(cleaned.desired.contains(where: \.temporary))
        _ = try await coordinator.setDisabled(false)
        let rolled = try await coordinator.rollbackLatest()
        XCTAssertTrue(rolled.disabled)
        XCTAssertEqual(rolled.managedProfile, "Work")
        let undo = try await coordinator.rollbackLatest()
        XCTAssertFalse(undo.disabled)
        XCTAssertEqual(undo.managedProfile, "Work")
        XCTAssertEqual(undo.desired.count, 1)
    }
    func testWarningsNeedCurrentPreparationForRestoreAndExternalReapply() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        let risky = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(8, output: 111)])
        do { _ = try await coordinator.apply(risky); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .riskConfirmationRequired) }
        _ = try await coordinator.apply(risky, riskConfirmed: true)
        _ = try await coordinator.setDisabled(true)
        do { _ = try await coordinator.setDisabled(false); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .riskConfirmationRequired) }
        let confirmation = try await coordinator.prepareRestore()
        _ = try await coordinator.setDisabled(false, confirmation: confirmation)
        port.external(port.read() + Data(" ".utf8))
        do { _ = try await coordinator.resolveExternal(.reapply, confirmation: confirmation); XCTFail() }
        catch { XCTAssertEqual(error as? KarabinerMappingError, .riskConfirmationRequired) }
        let current = try await coordinator.prepareRestore()
        _ = try await coordinator.resolveExternal(.reapply, confirmation: current)
    }
    func testProfileDiffRetainsEveryOutsideByteAndRuleOrder() throws {
        let plan = try KarabinerProfilePlanner.plan(mappingBase, profile: "Work", drafts: [mappingDraft()])
        XCTAssertEqual(plan.base.prefix(plan.diff.range.lowerBound), plan.bytes.prefix(plan.diff.range.lowerBound))
        XCTAssertEqual(plan.base.suffix(plan.base.count - plan.diff.range.upperBound), plan.bytes.suffix(plan.base.count - plan.diff.range.upperBound))
        let updated = try KarabinerProfilePlanner.plan(plan.bytes, profile: "Work", drafts: [mappingDraft(109)])
        XCTAssertEqual(updated.diff.previousRuleCount, 1)
        XCTAssertEqual(updated.bytes.prefix(updated.diff.range.lowerBound), plan.bytes.prefix(updated.diff.range.lowerBound))
        XCTAssertEqual(updated.userEvidence.rules.count, 1)
    }
    func testMissingContainersDuplicateProfilesMalformedMarkersAndJSON() throws {
        for input in [#"{"profiles":[{"name":"Work"}]}"#, #"{"profiles":[{"name":"Work","complex_modifications":{}}]}"#] {
            let plan = try KarabinerProfilePlanner.plan(Data(input.utf8), profile: "Work", drafts: [mappingDraft()])
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: plan.bytes))
        }
        for input in [#"{"profiles":[{"name":"Work"},{"name":"Work"}]}"#,
                      #"{"profiles":[{"name":"Work","name":"Other"}]}"#,
                      #"{"profiles":[{"name":"Work","complex_modifications":{"rules":[{"description":"KeyRecord managed block start","manipulators":[]}]}}]}"#] {
            XCTAssertThrowsError(try KarabinerProfilePlanner.plan(Data(input.utf8), profile: "Work", drafts: []))
        }
    }
    func testBatchConflictDomainsAndCycle() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        let conflicting = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(), mappingDraft()])
        XCTAssertTrue(conflicting.hasBlockingConflict)
        let disjoint = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(scope: .application("com.synthetic.a")), mappingDraft(scope: .application("com.synthetic.b"))])
        XCTAssertFalse(disjoint.hasBlockingConflict)
        let cycle = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(111, output: 109), mappingDraft(109, output: 111)])
        XCTAssertTrue(cycle.hasBlockingConflict)
        let devices = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(devices: [MappingDevice(vendorID: 1, productID: 1)]), mappingDraft(devices: [MappingDevice(vendorID: 2, productID: 2)])])
        XCTAssertFalse(devices.hasBlockingConflict)
        let chain = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft(111, output: 0)])
        XCTAssertTrue(chain.hasChainedMapping)
        XCTAssertTrue(chain.hasBlockingConflict)
        let before = port.writes
        do { _ = try await coordinator.apply(chain); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .conflict) }
        XCTAssertEqual(port.writes, before)
    }
    func testApplyVerifyDisableRestoreRollbackAndRollingBackups() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        let prepared = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft()])
        let applied = try await coordinator.apply(prepared)
        XCTAssertEqual(applied.batches.last?.state, .pendingVerification)
        XCTAssertNil(applied.batches.last?.verifiedAt)
        let verified = try await coordinator.verifyConfiguration()
        XCTAssertEqual(verified.batches.last?.verificationSource, "configurationReadback")
        let disabled = try await coordinator.setDisabled(true)
        XCTAssertTrue(disabled.disabled)
        XCTAssertEqual(disabled.desired.count, 1)
        let restored = try await coordinator.setDisabled(false)
        XCTAssertFalse(restored.disabled)
        for _ in 0..<9 { _ = try await coordinator.setDisabled(true); _ = try await coordinator.setDisabled(false) }
        let retained = try await coordinator.ledger()
        let backupCount = await store.backups.count
        XCTAssertEqual(retained.batches.count, 10)
        XCTAssertEqual(backupCount, 10)
        let beforeRollback = port.read()
        let rolledBack = try await coordinator.rollbackLatest()
        XCTAssertEqual(rolledBack.batches.last?.state, .rolledBack)
        XCTAssertNotEqual(port.read(), beforeRollback)
    }
    func testUnknownVersionAndChangesWithdrawPreparedOperation() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        let prepared = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft()])
        port.setRuntime(KarabinerRuntimeContext(version: nil, capabilities: BackendCapabilityCatalog.reference(.karabiner)))
        do { _ = try await coordinator.apply(prepared); XCTFail() } catch {}
        XCTAssertEqual(port.writes, 0)
        let unknown = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft()])
        do { _ = try await coordinator.apply(unknown); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .readOnlyVersion) }
        XCTAssertEqual(port.writes, 0)
        port.setRuntime(KarabinerRuntimeContext(version: "unknown", authority: .qualifiedAdapter(version: "unknown", testedProfiles: ["Work"]),
            capabilities: BackendCapabilityCatalog.reference(.karabiner)))
        let claimed = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft()])
        do { _ = try await coordinator.apply(claimed); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .readOnlyVersion) }
        XCTAssertEqual(port.writes, 0)
    }
    func testChangingProfilesCannotAbandonPreviouslyManagedRules() async throws {
        let port = MappingMemoryPort(), store = MappingMemoryStore()
        let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
        _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft()]))
        var draft = try mappingDraft(109); draft.profile = "Other"
        let other = try await coordinator.prepare(profile: "Other", drafts: [draft])
        do { _ = try await coordinator.apply(other); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .invalidDraft) }
        let ledger = try await coordinator.ledger()
        XCTAssertEqual(ledger.managedProfile, "Work")
        XCTAssertEqual(port.writes, 1)
    }
    func testWriteFailuresAndReadbackThreeClassifications() async throws {
        for mode in 1...4 {
            let port = MappingMemoryPort(), store = MappingMemoryStore()
            port.setMode(mode)
            let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
            let prepared = try await coordinator.prepare(profile: "Work", drafts: [mappingDraft()])
            do { _ = try await coordinator.apply(prepared) } catch {}
            let ledger = try await coordinator.ledger()
            XCTAssertEqual(ledger.batches.last?.state, mode == 1 ? .failed : mode == 2 ? .externallyChanged : .pendingVerification)
            XCTAssertNil(ledger.pending)
            XCTAssertEqual(port.writes, 1)
            if mode == 2 { XCTAssertEqual(port.read(), mappingBase + Data(" ".utf8)) }
        }
    }
    func testCrashReconcileUsesDurableJournalAndRefusesExternalRollback() async throws {
        for classification in 0..<3 {
            let port = MappingMemoryPort(), store = MappingMemoryStore()
            let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
            _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft()]))
            var ledger = try await coordinator.ledger()
            ledger.pending = ledger.batches.last?.id
            ledger.acceptedSHA256 = nil; ledger.managedProfile = nil; ledger.desired = []
            await store.set(ledger)
            if classification == 1 { port.external(mappingBase) }
            if classification == 2 { port.external(mappingBase + Data(" ".utf8)) }
            let reopened = KarabinerTransactionCoordinator(configuration: port, store: store)
            let recovered = try await reopened.reconcile()
            XCTAssertEqual(recovered.batches.last?.state, classification == 0 ? .pendingVerification : classification == 1 ? .failed : .externallyChanged)
            XCTAssertEqual(port.writes, 1)
            if classification == 2 {
                do { _ = try await reopened.rollbackLatest(); XCTFail() } catch { XCTAssertEqual(error as? KarabinerMappingError, .externalChange) }
                XCTAssertEqual(port.writes, 1)
            }
        }
    }
    func testExternalChoicesNeverSilentlyOverwrite() async throws {
        for choice in [KarabinerExternalChoice.adopt, .stopManaging, .reapply] {
            let port = MappingMemoryPort(), store = MappingMemoryStore()
            let coordinator = KarabinerTransactionCoordinator(configuration: port, store: store)
            _ = try await coordinator.apply(coordinator.prepare(profile: "Work", drafts: [mappingDraft()]))
            let changed = port.read() + Data(" ".utf8)
            port.external(changed)
            _ = try await coordinator.verifyConfiguration()
            let resolved = try await coordinator.resolveExternal(choice)
            switch choice {
            case .adopt:
                XCTAssertEqual(port.read(), changed); XCTAssertEqual(resolved.managedProfile, "Work")
                XCTAssertEqual(resolved.desired.count, 1); XCTAssertEqual(port.writes, 1)
            case .stopManaging:
                XCTAssertEqual(port.read(), changed); XCTAssertNil(resolved.managedProfile); XCTAssertEqual(port.writes, 1)
            case .reapply: XCTAssertEqual(port.writes, 2); XCTAssertEqual(resolved.batches.last?.state, .pendingVerification)
            }
        }
    }
}
