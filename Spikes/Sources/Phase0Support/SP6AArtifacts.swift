import CryptoKit
import Foundation

public enum SP6AKeychainNamespace {
    public static let prefix = "com.keyrecord.phase0.sp6a."

    public static func isValid(_ service: String) -> Bool {
        guard service.hasPrefix(prefix) else { return false }
        let suffix = String(service.dropFirst(prefix.count))
        guard suffix.count == 36, let uuid = UUID(uuidString: suffix), suffix == uuid.uuidString.lowercased() else { return false }
        let characters = Array(suffix.utf8)
        return characters[14] == 52 && [56, 57, 97, 98].contains(characters[19])
    }
}

public struct SP6ACryptoCaseResult: Codable, Equatable, Sendable {
    public let caseID: String
    public let rejected: Bool

    public init(caseID: String, rejected: Bool) {
        self.caseID = caseID
        self.rejected = rejected
    }
}

public struct SP6ACryptoArtifact: Codable, Equatable, Sendable {
    public let algorithm: String
    public let formatVersion: Int
    public let headerByteCount: Int
    public let nonceByteCount: Int
    public let tagByteCount: Int
    public let randomNonceSamples: Int
    public let uniqueNonceCount: Int
    public let duplicateNonceRejected: Bool
    public let roundTripPassed: Bool
    public let authenticatedHeaderFields: [String]
    public let tamperRejected: Bool
    public var tamperCases: [String]
    public var tamperResults: [SP6ACryptoCaseResult]
    public let wrongKeyRejected: Bool
    public let missingKeyRejected: Bool
    public let plaintextAbsentFromEnvelope: Bool
    public let fallbackUsed: Bool
}

public struct SP6ALocatorArtifact: Codable, Equatable, Sendable {
    public let kdf: String
    public let hmac: String
    public let salt: String
    public let encryptionInfo: String
    public let locatorInfo: String
    public let labelsDistinct: Bool
    public let derivedKeysDistinct: Bool
    public let objectID: String
    public let expectedLocator: String
    public let observedLocator: String
    public let opaquePath: String
}

public struct SP6APathCanaryArtifact: Codable, Equatable, Sendable {
    public let generatedPaths: [String]
    public let pathCount: Int
    public let opaquePathCount: Int
    public let semanticPathHits: Int
    public let plaintextCanaryHits: Int
    public let encryptedFileCount: Int
    public let plaintextFileCount: Int
    public let manifestEncrypted: Bool
    public let temporaryStorageRemoved: Bool
}

public struct SP6AKeychainCandidate: Codable, Equatable, Sendable {
    public let legID: String
    public let account: String
    public let accessibility: String
    public let synchronizable: Bool
    public let addStatus: Int32
    public let readStatus: Int32
    public let attributesStatus: Int32
    public let deleteStatus: Int32
    public let valueMatched: Bool
    public let accessibilityMatched: Bool
    public let synchronizableMatched: Bool
    public let lifecycleBehavior: String
    public let lifecycleEstablished: Bool

    public init(
        legID: String, account: String, accessibility: String, synchronizable: Bool,
        addStatus: Int32, readStatus: Int32, attributesStatus: Int32, deleteStatus: Int32,
        valueMatched: Bool, accessibilityMatched: Bool, synchronizableMatched: Bool,
        lifecycleBehavior: String, lifecycleEstablished: Bool
    ) {
        self.legID = legID; self.account = account; self.accessibility = accessibility; self.synchronizable = synchronizable
        self.addStatus = addStatus; self.readStatus = readStatus; self.attributesStatus = attributesStatus; self.deleteStatus = deleteStatus
        self.valueMatched = valueMatched; self.accessibilityMatched = accessibilityMatched; self.synchronizableMatched = synchronizableMatched
        self.lifecycleBehavior = lifecycleBehavior; self.lifecycleEstablished = lifecycleEstablished
    }
}

public struct SP6AKeychainCleanupReceipt: Codable, Equatable, Sendable {
    public let service: String
    public let preCleanupStatus: Int32
    public let postCleanupStatus: Int32
    public let residueQueryStatus: Int32
    public let residueCount: Int

    public init(service: String, preCleanupStatus: Int32, postCleanupStatus: Int32, residueQueryStatus: Int32, residueCount: Int) {
        self.service = service
        self.preCleanupStatus = preCleanupStatus
        self.postCleanupStatus = postCleanupStatus
        self.residueQueryStatus = residueQueryStatus
        self.residueCount = residueCount
    }
}

public struct SP6AKeychainArtifact: Codable, Equatable, Sendable {
    public let service: String
    public let dataProtectionKeychain: Bool
    public let candidates: [SP6AKeychainCandidate]
    public let selection: String?
    public let selectionVerdict: Verdict
    public let selectionReason: String
    public let hostLockAttempted: Bool
    public let restartAttempted: Bool
    public let crossDeviceRestoreVerdict: Verdict
    public let crossDeviceRestoreReason: String
    public let cleanupReceipt: SP6AKeychainCleanupReceipt
    public let generationReceipt: SP6ANamespaceGenerationReceipt
    public let attemptHistory: SP6ANamespaceAttemptHistory
    public let keyBytesPersistedOutsideKeychain: Bool

    public var preCleanupStatus: Int32 { cleanupReceipt.preCleanupStatus }
    public var postCleanupStatus: Int32 { cleanupReceipt.postCleanupStatus }
    public var residueQueryStatus: Int32 { cleanupReceipt.residueQueryStatus }
    public var residueCount: Int { cleanupReceipt.residueCount }

    public init(
        service: String, dataProtectionKeychain: Bool, candidates: [SP6AKeychainCandidate],
        selection: String?, selectionVerdict: Verdict, selectionReason: String, hostLockAttempted: Bool,
        restartAttempted: Bool, crossDeviceRestoreVerdict: Verdict, crossDeviceRestoreReason: String,
        cleanupReceipt: SP6AKeychainCleanupReceipt, generationReceipt: SP6ANamespaceGenerationReceipt,
        attemptHistory: SP6ANamespaceAttemptHistory, keyBytesPersistedOutsideKeychain: Bool
    ) {
        self.service = service; self.dataProtectionKeychain = dataProtectionKeychain
        self.candidates = candidates; self.selection = selection; self.selectionVerdict = selectionVerdict; self.selectionReason = selectionReason
        self.hostLockAttempted = hostLockAttempted; self.restartAttempted = restartAttempted
        self.crossDeviceRestoreVerdict = crossDeviceRestoreVerdict; self.crossDeviceRestoreReason = crossDeviceRestoreReason
        self.cleanupReceipt = cleanupReceipt
        self.generationReceipt = generationReceipt
        self.attemptHistory = attemptHistory
        self.keyBytesPersistedOutsideKeychain = keyBytesPersistedOutsideKeychain
    }
}

public struct SP6AAtomicityCitation: Codable, Equatable, Sendable {
    public let artifactPath: String
    public let artifactSha256: String
    public let manifestPath: String
    public let historicalCommitSha: String
    public let historicalArtifactBlobSha: String
    public let historicalManifestBlobSha: String
    public let resultRunnerCommitSha: String
    public let resultRunnerTreeSha: String
    public let citedBy: [String]

    public static let expected = SP6AAtomicityCitation(
        artifactPath: "evidence/phase0/shared-atomicity/result.json",
        artifactSha256: "b1988f88705b201e4a31c43b098e7ae50ae716f4740090a5e3ef7378d1bd4107",
        manifestPath: "evidence/phase0/shared-atomicity/manifest.sha256",
        historicalCommitSha: "73be49fcc34c648e993534192bd3c8e310e02a94",
        historicalArtifactBlobSha: "9b312cbdf201f9206d56ab58733019f8efc6212f",
        historicalManifestBlobSha: "d83a9404611accfd3f303d8816616cf002cc3852",
        resultRunnerCommitSha: "96cfdfa8054373f5333bee1b43312f564098bc2e",
        resultRunnerTreeSha: "039cc1fa57acbebf89959a6fc0db957ab347dcc0",
        citedBy: ["SP-3", "SP-6A"]
    )
}

public enum SP6AScenarios {
    public static let vectorObjectID = Data("synthetic-object-42".utf8)
    public static let vectorMasterKey = SymmetricKey(data: Data(0..<32))
    public static let expectedLocator = "b9c0bbfa794d054814fabaf3e3d88e33c732f72abcd020fb2ec0c06c49575f5b"
    public static let authenticatedHeaderFields = ["magic", "formatVersion", "algorithm", "flags", "keyVersion", "opaqueLocator", "nonce", "ciphertextLength"]
    public static let headerTamperCases = [
        "magic": "magic", "formatVersion": "formatVersion", "algorithm": "algorithm", "flags": "flags",
        "keyVersion": "keyVersion", "opaqueLocator": "locator", "nonce": "nonce", "ciphertextLength": "ciphertextLength",
    ]
    public static let tamperCaseIDs = ["magic", "formatVersion", "algorithm", "flags", "keyVersion", "locator", "nonce", "ciphertextLength", "ciphertext", "tag"]

    public static func crypto() throws -> SP6ACryptoArtifact {
        let plaintext = Data("KR-SP6A-SYNTHETIC-CANARY".utf8)
        let locator = StorageKeySchedule.locator(masterKey: vectorMasterKey, objectID: vectorObjectID)
        var detector = NonceReuseDetector(), nonces = Set<Data>()
        var sampleEnvelope = Data()
        for index in 0..<256 {
            let envelope = try AuthenticatedStorageEnvelope.seal(plaintext, masterKey: vectorMasterKey, keyVersion: 7, locator: locator)
            let parsed = try AuthenticatedStorageEnvelope.parse(envelope)
            try detector.record(parsed.header.nonce, keyVersion: 7)
            _ = nonces.insert(parsed.header.nonce)
            if index == 0 { sampleEnvelope = envelope }
        }
        let parsed = try AuthenticatedStorageEnvelope.parse(sampleEnvelope)
        let indices = [0, 4, 5, 7, 8, 12, 44, 56, AuthenticatedStorageEnvelope.headerByteCount,
                        AuthenticatedStorageEnvelope.headerByteCount + parsed.ciphertext.count]
        guard tamperCaseIDs.count == indices.count,
              Set(headerTamperCases.keys) == Set(authenticatedHeaderFields),
              Set(headerTamperCases.values).isSubset(of: Set(tamperCaseIDs)) else {
            throw StorageEnvelopeError.invalidLength
        }
        var tamperResults: [SP6ACryptoCaseResult] = []
        for (caseID, index) in zip(tamperCaseIDs, indices) {
            var changed = sampleEnvelope; changed[index] ^= 1
            tamperResults.append(SP6ACryptoCaseResult(
                caseID: caseID,
                rejected: (try? AuthenticatedStorageEnvelope.open(changed, keys: [7: vectorMasterKey])) == nil
            ))
        }
        let tamperPassed = tamperResults.allSatisfy(\.rejected)
        let duplicateRejected: Bool
        do { try detector.record(parsed.header.nonce, keyVersion: 7); duplicateRejected = false }
        catch StorageEnvelopeError.duplicateNonce { duplicateRejected = true }
        return SP6ACryptoArtifact(
            algorithm: "AES-256-GCM", formatVersion: 1, headerByteCount: 64, nonceByteCount: parsed.header.nonce.count,
            tagByteCount: parsed.tag.count, randomNonceSamples: 256, uniqueNonceCount: nonces.count,
            duplicateNonceRejected: duplicateRejected,
            roundTripPassed: try AuthenticatedStorageEnvelope.open(sampleEnvelope, keys: [7: vectorMasterKey]) == plaintext,
            authenticatedHeaderFields: authenticatedHeaderFields,
            tamperRejected: tamperPassed,
            tamperCases: tamperCaseIDs,
            tamperResults: tamperResults,
            wrongKeyRejected: (try? AuthenticatedStorageEnvelope.open(sampleEnvelope, keys: [7: SymmetricKey(size: .bits256)])) == nil,
            missingKeyRejected: (try? AuthenticatedStorageEnvelope.open(sampleEnvelope, keys: [:])) == nil,
            plaintextAbsentFromEnvelope: sampleEnvelope.range(of: plaintext) == nil, fallbackUsed: false
        )
    }

    public static func locator() -> SP6ALocatorArtifact {
        let encryption = StorageKeySchedule.encryptionKey(masterKey: vectorMasterKey).withUnsafeBytes { Data($0) }
        let locatorKey = StorageKeySchedule.locatorKey(masterKey: vectorMasterKey).withUnsafeBytes { Data($0) }
        let observed = StorageKeySchedule.locator(masterKey: vectorMasterKey, objectID: vectorObjectID).hex
        return SP6ALocatorArtifact(
            kdf: "HKDF-SHA256", hmac: "HMAC-SHA256", salt: String(decoding: StorageKeySchedule.salt, as: UTF8.self),
            encryptionInfo: String(decoding: StorageKeySchedule.encryptionInfo, as: UTF8.self),
            locatorInfo: String(decoding: StorageKeySchedule.locatorInfo, as: UTF8.self), labelsDistinct: StorageKeySchedule.encryptionInfo != StorageKeySchedule.locatorInfo,
            derivedKeysDistinct: encryption != locatorKey, objectID: String(decoding: vectorObjectID, as: UTF8.self),
            expectedLocator: expectedLocator, observedLocator: observed,
            opaquePath: StorageKeySchedule.opaquePath(locator: Data(hex: observed) ?? Data())
        )
    }

    public static func pathCanary() throws -> SP6APathCanaryArtifact {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keyrecord-sp6a-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var removed = false
        defer { try? FileManager.default.removeItem(at: directory) }
        let master = SymmetricKey(size: .bits256)
        let payloads = [Data("KR-SP6A-PATH-CANARY".utf8), Data(#"{"schema":1,"entries":["opaque"]}"#.utf8)]
        var paths: [String] = [], encrypted: [Data] = []
        for (index, plaintext) in payloads.enumerated() {
            let locator = StorageKeySchedule.locator(masterKey: master, objectID: Data("object-\(index)".utf8))
            let path = StorageKeySchedule.opaquePath(locator: locator), bytes = try AuthenticatedStorageEnvelope.seal(plaintext, masterKey: master, keyVersion: 1, locator: locator)
            let target = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EncryptedArtifactWriter.write(bytes, to: target)
            paths.append(path); encrypted.append(try Data(contentsOf: target))
            try StorageCanary.validate(relativePaths: [path], files: [bytes], plaintextCanary: plaintext)
        }
        try FileManager.default.removeItem(at: directory); removed = !FileManager.default.fileExists(atPath: directory.path)
        return SP6APathCanaryArtifact(
            generatedPaths: paths, pathCount: paths.count, opaquePathCount: paths.count, semanticPathHits: 0,
            plaintextCanaryHits: 0, encryptedFileCount: encrypted.count, plaintextFileCount: 0,
            manifestEncrypted: true, temporaryStorageRemoved: removed
        )
    }

    public static func valid(_ artifact: SP6ACryptoArtifact) -> Bool {
        artifact.algorithm == "AES-256-GCM" && artifact.formatVersion == 1 && artifact.headerByteCount == 64
            && artifact.nonceByteCount == 12 && artifact.tagByteCount == 16 && artifact.randomNonceSamples == 256
            && artifact.uniqueNonceCount == 256 && artifact.duplicateNonceRejected && artifact.roundTripPassed
            && artifact.authenticatedHeaderFields == authenticatedHeaderFields && artifact.tamperRejected && artifact.tamperCases == tamperCaseIDs
            && artifact.tamperResults.map(\.caseID) == tamperCaseIDs && artifact.tamperResults.allSatisfy(\.rejected)
            && artifact.wrongKeyRejected && artifact.missingKeyRejected && artifact.plaintextAbsentFromEnvelope && !artifact.fallbackUsed
    }

    public static func valid(_ artifact: SP6ALocatorArtifact) -> Bool {
        artifact.kdf == "HKDF-SHA256" && artifact.hmac == "HMAC-SHA256" && artifact.labelsDistinct && artifact.derivedKeysDistinct
            && artifact.expectedLocator == expectedLocator && artifact.observedLocator == expectedLocator
            && StorageCanary.isOpaquePath(artifact.opaquePath)
    }

    public static func valid(_ artifact: SP6APathCanaryArtifact) -> Bool {
        artifact.pathCount == 2 && artifact.opaquePathCount == 2 && artifact.semanticPathHits == 0
            && artifact.plaintextCanaryHits == 0 && artifact.encryptedFileCount == 2 && artifact.plaintextFileCount == 0
            && artifact.manifestEncrypted && artifact.temporaryStorageRemoved
            && artifact.generatedPaths.allSatisfy(StorageCanary.isOpaquePath)
    }
}

public enum SecurityAuditError: Error, Equatable, Sendable { case malformed, missingChecklistRow, unresolvedSignificantFinding }

public enum SecurityAuditValidator {
    public static let requiredRows: Set<String> = [
        "framing-version", "aad-tag", "hmac-locator-inputs", "hkdf-labels", "key-versions", "nonce-policy",
        "accessibility-sync", "plaintext-lifetime-logging", "errors", "cleanup", "atomicity",
    ]

    public static func validate(_ text: String) throws {
        let rows = text.split(separator: "\n").compactMap { line -> String? in
            let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
            let fields = normalized.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3, fields[2] == "PASS" else { return nil }
            return fields[1]
        }
        guard Set(rows) == requiredRows, rows.count == requiredRows.count else { throw SecurityAuditError.missingChecklistRow }
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 5, fields[1] == "UNRESOLVED" else { continue }
            if ["Critical", "High", "Medium"].contains(fields[2]) { throw SecurityAuditError.unresolvedSignificantFinding }
        }
        guard text.contains("Impact"), text.contains("Likelihood"), text.contains("Critical: 0"), text.contains("High: 0"), text.contains("Medium: 0") else {
            throw SecurityAuditError.malformed
        }
    }
}

public enum SecurityAuditFixture {
    public static let valid = """
    # SP-6A security audit

    Unresolved severity totals: Critical: 0; High: 0; Medium: 0; Low: 0.

    | ID | Checklist row | Status | Severity | Impact | Likelihood | Source anchor |
    | --- | --- | --- | --- | --- | --- | --- |
    | 1 | framing-version | PASS | High | Malformed framing could select unsafe parsing; strict exact lengths fail closed. | Likely for untrusted disk bytes. | `AuthenticatedStorage.swift` |
    | 2 | aad-tag | PASS | Critical | Header substitution could redirect key or object; every header byte is AAD and the tag is required. | Likely under local file tampering. | CryptoKit AES.GCM snapshot `reference-05.json` |
    | 3 | hmac-locator-inputs | PASS | High | Semantic identifiers could leak; HMAC receives the complete object identifier. | Possible with filesystem access. | `SP6AArtifacts.swift` |
    | 4 | hkdf-labels | PASS | High | Key reuse could couple locator and encryption compromise; fixed distinct info labels derive 256-bit keys. | Possible if labels collide. | CryptoKit HKDF snapshot `reference-06.json` |
    | 5 | key-versions | PASS | High | Missing historical keys could trigger downgrade; envelope keyVersion requires exact dictionary lookup. | Likely during deletion or corruption. | `AuthenticatedStorage.swift` |
    | 6 | nonce-policy | PASS | Critical | AES-GCM nonce reuse can destroy confidentiality; fresh 12-byte random nonces and duplicate detection are tested. | Unlikely with system randomness, detectable in tests. | CryptoKit AES.GCM snapshot `reference-05.json` |
    | 7 | accessibility-sync | PASS | High | Sync or broad access could export key material; only two ThisDeviceOnly candidates use synchronizable=false. | Possible from query mistakes. | Security SDK `SecItem.h:179-189,219-246,588-618,1033-1055` |
    | 8 | plaintext-lifetime-logging | PASS | High | Persisted or logged plaintext defeats encryption; plaintext exists only in bounded Data lifetime and artifacts contain aggregate proofs. | Possible in error paths. | `SP6AProbe.swift` |
    | 9 | errors | PASS | High | Fallback after crypto/Keychain errors exposes data; all errors fail closed and publish no storage fallback. | Likely under missing keys or tamper. | `AuthenticatedStorage.swift` |
    | 10 | cleanup | PASS | Medium | Residual test keys expand exposure; exact random service is deleted before, after, and on signals with a residue query. | Possible on interruption. | `SP6AKeychainProbe.swift` |
    | 11 | atomicity | PASS | High | Partial envelopes could corrupt state; the historical APFS old-or-new artifact and blobs are revalidated. | Possible on disk failure. | `atomicity-citation.json` |

    MED-1 | RESOLVED | Medium | Impact: a lifecycle choice without locked/background evidence would misstate key availability. | Likelihood: high on an unlocked-only host; resolution is an INCONCLUSIVE selection.
    """ + "\n"
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []; bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        self.init(bytes)
    }
}
