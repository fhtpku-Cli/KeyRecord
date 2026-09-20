import Foundation

/// Receipt written by the bounded harness.
///
/// Privacy contract: every field is an outcome code, a count, or a coarse state string.
/// There is deliberately no field capable of holding typed text, key codes, a raw event
/// sequence, or per-event timestamps. The single timestamp recorded is the run's own
/// wall-clock start, which is run metadata, not user behaviour.
struct HarnessReport: Codable {
    let outcome: String       // COMPLETED | BLOCKED | FAIL
    let code: String
    let seconds: Int
    let mode: String
    let counters: LayeredCounters
    var startedAt: String = ISO8601DateFormatter().string(from: Date())
    var host: HostFacts = .current

    struct HostFacts: Codable {
        let macOSVersion: String
        let architecture: String
        let karabinerDaemonPresent: Bool

        static var current: HostFacts {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            // Presence only, as a recorded condition of the run. The harness never starts,
            // stops or otherwise touches Karabiner.
            let present = FileManager.default.fileExists(
                atPath: "/Library/Application Support/org.pqrs/Karabiner-Elements")
            return HostFacts(macOSVersion:
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                architecture: architecture, karabinerDaemonPresent: present)
        }
    }

    /// Human-readable one-line verdict naming WHICH layer stopped, so a zero count is
    /// never reported as a bare "capture doesn't work".
    var diagnosis: String {
        if outcome != "COMPLETED" { return "\(outcome): \(code)" }
        if counters.totalTapCallbacks == 0 {
            return "layer 1: tap callback never fired — no keyboard event reached this process"
        }
        if counters.handoffAccepted == 0 && counters.handoffClosed > 0 {
            return "layer 2: callback fired but the queue rejected every event (gate closed)"
        }
        if counters.normalizationOutput == 0 {
            return "layer 3: events accepted but normalization produced no output"
        }
        if counters.aggregateDelta == 0 {
            return "layer 4: normalization ran but the aggregate never moved"
        }
        return "layers 1-4 OK: tap -> queue -> normalization -> aggregate all advanced"
    }

    func emit(to url: URL?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n\(diagnosis)\n".utf8))
        if let url { try? data.write(to: url) }
    }
}
