import CryptoKit
import Foundation

public enum Preflight {
    public static func evaluate(data: Data?, context: PreflightContext, now: Date) -> PreflightVerdict {
        guard let data else { return .blocked(.missingManifest) }
        guard let manifest = try? JSONDecoder().decode(HostManifest.self, from: data), manifest.schemaVersion == 1 else {
            return .blocked(.malformedManifest)
        }
        guard let expiry = ISO8601DateFormatter().date(from: manifest.expiresAt), expiry > now else { return .blocked(.expired) }
        let live = context.identity
        guard !manifest.hostID.isEmpty, manifest.hostID == live.hostID else { return .blocked(.hostIDMismatch) }
        guard ["arm64", "x86_64"].contains(manifest.architecture),
              manifest.architecture == live.architecture else { return .blocked(.architectureMismatch) }
        guard manifest.macOS == live.macOS else { return .blocked(.macOSMismatch) }
        guard live.signatureValid else { return .blocked(.unavailableIdentity) }
        guard !manifest.teamID.isEmpty, manifest.teamID == live.teamID else { return .blocked(.teamIDMismatch) }
        guard digest(manifest.certificateSHA256),
              manifest.certificateSHA256 == live.certificateSHA256 else { return .blocked(.certificateFingerprintMismatch) }
        guard manifest.bundleIDs == ["com.keyrecord.phase1.probe.host", "com.keyrecord.phase1.probe.tests"],
              manifest.bundleIDs == live.bundleIDs else { return .blocked(.bundleIDsMismatch) }
        guard live.entitlementsValid else { return .blocked(.entitlementsMismatch) }
        guard manifest.namespacePrefix == ProbeNamespace.prefix else { return .blocked(.namespaceMismatch) }
        guard manifest.scratchRoot == context.scratchRoot, manifest.scratchRoot.hasPrefix("/"),
              !manifest.scratchRoot.split(separator: "/").contains("..") else { return .blocked(.scratchRootMismatch) }
        guard manifest.attemptID == context.attemptID, !manifest.attemptID.isEmpty else { return .blocked(.attemptMismatch) }
        guard Set(manifest.operations) == Set(HostOperation.allCases),
              manifest.operations.count == HostOperation.allCases.count else { return .blocked(.operationAllowlistMismatch) }
        guard manifest.controllerPath.hasPrefix("/"), context.controllerExists else { return .blocked(.controllerMissing) }
        guard context.controllerRegular else { return .blocked(.controllerNotRegular) }
        guard context.controllerExecutable else { return .blocked(.controllerNotExecutable) }
        guard digest(manifest.controllerSHA256),
              manifest.controllerSHA256 == context.controllerSHA256 else { return .blocked(.controllerHashMismatch) }
        return .ready
    }

    private static func digest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public struct ProbeNamespace: Equatable, Sendable {
    public static let prefix = "com.keyrecord.phase1.probe."
    public let service: String
    public init(attempt: String, seed: UUID) {
        let input = Data((attempt + "\0" + seed.uuidString).utf8)
        service = Self.prefix + SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
