import Foundation

public struct LifecycleBlockedCause: Codable {
    public let schemaVersion: Int
    public let status: LifecycleStatus
    public let exitCode: Int32
    public let reason: String
    public let missing: [String]
    public let recovery: [String]
    public let unobservableAssertions: [String]
    public let independentBlockedScenarios: [String: String]
    public let artifacts: [LifecycleScenarioArtifact]
    public let keychainCalls: Int
    public let controllerCalls: Int
    public let keychainEffects: Int
    public let isFailure: Bool

    public static func noController() throws -> LifecycleBlockedCause {
        let artifacts = try LifecycleScenario.allCases.map { try LifecycleScenarioMachine.artifact(for: $0, controller: nil) }
        return .init(
            schemaVersion: 1,
            status: .blocked,
            exitCode: 2,
            reason: "controllerMissing",
            missing: [
                "A/host.json authorized for this host, attempt, operation allowlist and expiry",
                "approved noninteractive controller executable with matching SHA256",
                "valid signing certificate and Team ID for the hosted probe",
                "authoritative controller-provided unlocked witness for each current process generation",
            ],
            recovery: [
                "supply the private authorized A/host.json outside Git",
                "install the approved controller and bind its exact SHA256",
                "sign KeychainLifecycleProbe with the authorized certificate and Team ID",
                "run the registered host sp6a case without lock, sleep, restart or logout prompts",
                "provide a second separately authorized device before cross-device restore qualification",
            ],
            unobservableAssertions: ReadinessContract.assertions,
            independentBlockedScenarios: ["crossDeviceRestore": "secondAuthorizedDeviceMissing"],
            artifacts: artifacts,
            keychainCalls: 0,
            controllerCalls: 0,
            keychainEffects: 0,
            isFailure: false
        )
    }
}

enum ReadinessContract {
    static let assertions = [
        "t7.keychain.whenUnlockedThisDeviceOnly",
        "t7.keychain.nonSynchronizable",
        "t7.lock.authoritativeInitialState",
        "t7.lock.generationFence",
        "t7.restart.unlocked",
        "t7.restart.startupLocked",
        "t7.sleep.captureClosed",
        "t7.wake.authoritativeUnlock",
    ]
}
