import CryptoKit
import Foundation
import Security

public enum LivePreflight {
    public static func evaluate(manifestURL: URL, attempt: URL) -> PreflightVerdict {
        guard manifestURL.path == attempt.appendingPathComponent("host.json").path,
              manifestURL.resolvingSymlinksInPath().path == manifestURL.path,
              attempt.resolvingSymlinksInPath().path == attempt.path else { return .blocked(.scratchRootMismatch) }
        guard let data = try? Data(contentsOf: manifestURL) else { return .blocked(.missingManifest) }
        guard let manifest = try? JSONDecoder().decode(HostManifest.self, from: data) else { return .blocked(.malformedManifest) }
        do {
            let host = attempt.appendingPathComponent("build/lifecycle/Build/Products/Debug/KeychainLifecycleProbe.app")
            let tests = host.appendingPathComponent("Contents/PlugIns/KeychainLifecycleTests.xctest")
            let hostSignature = try signature(host)
            let testSignature = try signature(tests)
            let controller = URL(fileURLWithPath: manifest.controllerPath)
            guard manifest.controllerPath.hasPrefix("/"), FileManager.default.fileExists(atPath: controller.path)
            else { return .blocked(.controllerMissing) }
            guard controller.path == controller.resolvingSymlinksInPath().path,
                  let attributes = try? controller.resourceValues(forKeys: [.isRegularFileKey]), attributes.isRegularFile == true
            else { return .blocked(.controllerNotRegular) }
            guard FileManager.default.isExecutableFile(atPath: controller.path) else { return .blocked(.controllerNotExecutable) }
            guard let bytes = try? Data(contentsOf: controller, options: .mappedIfSafe) else { return .blocked(.controllerHashMismatch) }
            let identity = HostIdentity(
                hostID: try read("/usr/sbin/sysctl", ["-n", "kern.uuid"]),
                architecture: try read("/usr/bin/uname", ["-m"]), macOS: try read("/usr/bin/sw_vers", ["-productVersion"]),
                certificateSHA256: hostSignature.fingerprint, teamID: hostSignature.team,
                bundleIDs: [hostSignature.identifier, testSignature.identifier],
                signatureValid: hostSignature.fingerprint == testSignature.fingerprint && hostSignature.team == testSignature.team,
                entitlementsValid: hostSignature.entitled && testSignature.entitled)
            let context = PreflightContext(identity: identity, attemptID: attempt.lastPathComponent, scratchRoot: attempt.path,
                                           controllerSHA256: sha256(bytes), controllerExecutable: true,
                                           controllerExists: true, controllerRegular: true)
            return Preflight.evaluate(data: data, context: context, now: Date())
        } catch let block as PreflightBlock { return .blocked(block) }
        catch { return .blocked(.unavailableIdentity) }
    }

    private struct Signature {
        let fingerprint: String
        let team: String
        let identifier: String
        let entitled: Bool
    }

    private static func signature(_ url: URL) throws -> Signature {
        // codesign verifies the disk bundle read-only; Security extracts certificate DER and entitlements.
        _ = try read("/usr/bin/codesign", ["--verify", "--strict", url.path])
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw PreflightBlock.unavailableIdentity }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let identifier = info[kSecCodeInfoIdentifier as String] as? String else { throw PreflightBlock.unavailableIdentity }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let applicationID = entitlements?["com.apple.application-identifier"] as? String
        let entitlementTeam = entitlements?["com.apple.developer.team-identifier"] as? String
        let groups = entitlements?["keychain-access-groups"] as? [String]
        let expectedGroup = team + ".com.keyrecord.phase1.probe.host"
        return Signature(fingerprint: sha256(SecCertificateCopyData(leaf) as Data), team: team, identifier: identifier,
                         entitled: applicationID == team + "." + identifier && entitlementTeam == team && groups == [expectedGroup])
    }

    private static func read(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PreflightBlock.unavailableIdentity }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
