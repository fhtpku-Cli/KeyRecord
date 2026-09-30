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
                entitlementsValid: hostSignature.policyValid && testSignature.policyValid)
            let context = PreflightContext(identity: identity, attemptID: attempt.lastPathComponent, scratchRoot: attempt.path,
                                           controllerSHA256: sha256(bytes), controllerExecutable: true,
                                           controllerExists: true, controllerRegular: true)
            return Preflight.evaluate(data: data, context: context, now: Date())
        } catch let block as PreflightBlock { return .blocked(block) }
        catch { return .blocked(.unavailableIdentity) }
    }

    struct Signature {
        let fingerprint: String
        let team: String
        let identifier: String
        let policyValid: Bool
    }

    static func signature(_ url: URL) throws -> Signature {
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
        guard let executable = Bundle(url: url)?.executableURL else { throw PreflightBlock.unavailableIdentity }
        let headers = try read("/usr/bin/otool", ["-hv", executable.path])
        return Signature(fingerprint: sha256(SecCertificateCopyData(leaf) as Data), team: team, identifier: identifier,
                         policyValid: signingPolicyValid(identifier: identifier, team: team,
                                                         entitlements: entitlements, machHeaders: headers))
    }

    static func signingPolicyValid(identifier: String, team: String,
                                   entitlements: [String: Any]?, machHeaders: String) -> Bool {
        guard !team.isEmpty else { return false }
        let types = machHeaders.split(separator: "\n").compactMap { line -> String? in
            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard let magic = columns.first, magic.hasPrefix("MH_") else { return nil }
            guard ["MH_MAGIC", "MH_CIGAM", "MH_MAGIC_64", "MH_CIGAM_64"].contains(String(magic)),
                  columns.count > 4 else { return "" }
            return String(columns[4])
        }
        guard !types.isEmpty else { return false }
        switch identifier {
        case "com.keyrecord.phase1.probe.host":
            return types.allSatisfy { $0 == "EXECUTE" } &&
                entitlements?["com.apple.application-identifier"] as? String == team + "." + identifier &&
                entitlements?["com.apple.developer.team-identifier"] as? String == team &&
                entitlements?["keychain-access-groups"] as? [String] == [team + "." + identifier]
        case "com.keyrecord.phase1.probe.tests":
            // The in-process test plug-in uses the verified host's entitlements.
            // Its own signature/team/certificate and bundle identity remain mandatory.
            return types.allSatisfy { $0 == "BUNDLE" } && (entitlements?.isEmpty ?? true)
        default:
            return false
        }
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
