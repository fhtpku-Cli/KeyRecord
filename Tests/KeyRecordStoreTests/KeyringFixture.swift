import Foundation
import XCTest
import KeyRecordCore
@testable import KeyRecordStore

let v1 = KeyVersion(rawValue: 1)
let v2 = KeyVersion(rawValue: 2)

actor KeyringTrace {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

enum SimulatedCrash: Error { case interrupted }

actor FakeKeychain: KeychainBackend {
    var items: [KeychainItemID: Data] = [:]
    var additions: [KeychainItem] = []
    var failure: (String, Bool)?
    var duplicate = false
    var suspendedRead: CheckedContinuation<Data?, Never>?
    var readStarted: CheckedContinuation<Void, Never>?
    var delayRead = false
    var cancellationObserved = false
    let trace: KeyringTrace

    init(trace: KeyringTrace) { self.trace = trace }
    func seed(_ id: KeychainItemID, bytes: Data?) { items[id] = bytes }
    func fail(_ event: String, after: Bool) { failure = (event, after) }
    func forceDuplicate() { duplicate = true }
    func delayNextRead() { delayRead = true }
    func waitForRead() async {
        if suspendedRead != nil { return }
        await withCheckedContinuation { readStarted = $0 }
    }
    func resumeRead() { suspendedRead?.resume(returning: Data(repeating: 7, count: 32)); suspendedRead = nil }

    func read(_ id: KeychainItemID) async throws -> Data? {
        if delayRead, id.account != "metadata" {
            delayRead = false
            let bytes = await withCheckedContinuation { continuation in
                suspendedRead = continuation
                readStarted?.resume(); readStarted = nil
            }
            cancellationObserved = Task.isCancelled
            return bytes // Deliberately uncooperative callback must still be fenced.
        }
        return items[id]
    }

    func versions(in namespace: KeychainNamespace) async throws -> Set<KeyVersion> {
        Set(items.keys.filter { $0.namespace == namespace }.compactMap(\.version))
    }

    func add(_ item: KeychainItem) async throws {
        try checkpoint("add", after: false)
        guard !duplicate, items[item.id] == nil else { throw KeyringError.duplicateItem }
        items[item.id] = item.material
        additions.append(item)
        await trace.record("add")
        try checkpoint("add", after: true)
    }

    func publish(_ update: KeychainMetadataUpdate) async throws {
        let next = try KeyringMetadata.decode(update.replacement)
        let previous = try update.expected.map(KeyringMetadata.decode)
        let event: String
        if previous == nil { event = "bootstrap" }
        else if next.current != previous?.current { event = "publish" }
        else if !next.retirementPending.isEmpty { event = "mark" }
        else { event = "remove" }
        try checkpoint(event, after: false)
        guard items[update.id] == update.expected else { throw KeyringError.metadataConflict }
        items[update.id] = update.replacement
        await trace.record(event)
        try checkpoint(event, after: true)
    }

    func delete(_ id: KeychainItemID) async throws {
        try checkpoint("delete", after: false)
        items[id] = nil
        await trace.record("delete")
        try checkpoint("delete", after: true)
    }

    private func checkpoint(_ event: String, after: Bool) throws {
        if let failure, failure.0 == event, failure.1 == after {
            self.failure = nil
            throw SimulatedCrash.interrupted
        }
    }
}

struct FakeEntropy: MasterMaterialGenerating {
    var denied = false
    func generate() throws -> Data {
        guard !denied else { throw KeyringError.entropyDenied }
        return Data(repeating: 7, count: 32)
    }
}

struct FakeKeyringClock: KeyringClock {
    func now() -> Date { Date(timeIntervalSince1970: 100) }
}

actor FakeStoreState: KeyringCreationAuthorizing {
    var state = KeyringCreationState(consent: true, store: .fresh)
    func set(_ value: KeyringCreationState) { state = value }
    func creationState() async throws -> KeyringCreationState { state }
}

actor FakeReferences: ProtectedReferenceProviding, ProtectedReferenceSession {
    let trace: KeyringTrace
    var references: [ProtectedReference] = []
    var coverage = Set(ProtectedReferenceKind.allCases)
    var failure: String?
    var active = false
    var scans = 0
    var releaseCount = 0
    var releaseGate: KeyAvailabilityGate?
    var lastAccess: KeyringProtectedAccess?
    var materialCounts: [Int] = []
    var removeOnScan: (FakeKeychain, KeychainItemID)?
    var pausedEvent: String?
    var paused: CheckedContinuation<Void, Never>?
    var pauseStarted: CheckedContinuation<Void, Never>?
    init(trace: KeyringTrace) { self.trace = trace }
    func set(_ values: [ProtectedReference]) { references = values }
    func incomplete() { coverage.remove(.fixedManifest) }
    func fail(_ event: String) { failure = event }
    func lockOnRelease(_ gate: KeyAvailabilityGate) { releaseGate = gate }
    func removeAtScan(_ backend: FakeKeychain, id: KeychainItemID) { removeOnScan = (backend, id) }
    func pauseAt(_ event: String) { pausedEvent = event }
    func waitForPause() async {
        if paused != nil { return }
        await withCheckedContinuation { pauseStarted = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
    func acquireExclusiveAccess() async throws -> any ProtectedReferenceSession {
        guard !active else { throw KeyringError.busy }
        active = true
        return self
    }
    func migrateData(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await step("migrate")
        lastAccess = access
        materialCounts = [try await access.withMaterial(rotation.from) { $0.count },
                          try await access.withMaterial(rotation.to) { $0.count }]
    }
    func reencryptManifestAndJournals(_ rotation: KeyRotation, access: KeyringProtectedAccess) async throws {
        try await step("reencrypt")
    }
    func recoverAndReconcile(access: KeyringProtectedAccess) async throws { try await step("reconcile") }
    func scan(access: KeyringProtectedAccess) async throws -> ProtectedReferenceSnapshot {
        scans += 1
        try await step("scan")
        if let (backend, id) = removeOnScan { await backend.seed(id, bytes: nil); removeOnScan = nil }
        return ProtectedReferenceSnapshot(coverage: coverage, references: references)
    }
    func release() async {
        releaseCount += 1
        active = false
        releaseGate?.update(.locked)
    }
    private func step(_ event: String) async throws {
        await trace.record(event)
        if pausedEvent == event {
            pausedEvent = nil
            await withCheckedContinuation { continuation in
                paused = continuation
                pauseStarted?.resume(); pauseStarted = nil
            }
        }
        if failure == event { failure = nil; throw SimulatedCrash.interrupted }
    }
}

struct KeyringFixture {
    let namespace = try! KeychainNamespace("com.keyrecord.tests.keyring.fixture")
    let trace: KeyringTrace
    let backend: FakeKeychain
    let state = FakeStoreState()
    let references: FakeReferences
    let gate = KeyAvailabilityGate()
    let ring: KeychainKeyring

    init(entropyDenied: Bool = false) {
        trace = KeyringTrace()
        backend = FakeKeychain(trace: trace)
        references = FakeReferences(trace: trace)
        ring = KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace), ports: KeyringPorts(
            backend: backend, entropy: FakeEntropy(denied: entropyDenied), creation: state,
            references: references, clock: FakeKeyringClock()), gate: gate)
        gate.update(.unlocked)
    }
    func reopen() -> KeychainKeyring {
        KeychainKeyring(configuration: KeyringConfiguration(namespace: namespace), ports: KeyringPorts(
            backend: backend, entropy: FakeEntropy(), creation: state,
            references: references, clock: FakeKeyringClock()), gate: gate)
    }
    func key(_ version: KeyVersion) -> KeychainItemID { .key(namespace, version) }
    var metadataID: KeychainItemID { .metadata(namespace) }
}

@MainActor
func expectKeyringError<T>(
    _ expected: KeyringError, operation: () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await operation(); XCTFail("Expected typed rejection", file: file, line: line) }
    catch { XCTAssertEqual(error as? KeyringError, expected, file: file, line: line) }
}
