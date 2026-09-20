import Foundation

/// Pure decision for the menu-bar status line.
///
/// Lives in Core so it can be tested without linking the App's whole composition graph,
/// and so the rule has exactly one definition.
///
/// KR-08 (found by live verification, not by code review): the menu bar read
/// `● Collecting` while the process held no store handle, wrote nothing, and counted
/// nothing from real key presses. The old rule consulted only `phase` and the
/// key-availability gate — neither of which witnesses a live event source. On the
/// restart-recovery path `boot()` primes the key gate to `.unlocked` and a restored
/// `expectedCollecting=true` carries the phase toward collecting, so both inputs looked
/// healthy while capture had never started.
///
/// Rule: a "Collecting" claim requires a live capture session. Otherwise fail closed and
/// name a reason.
public enum CaptureStatusPresentation {
    public static func title(phase: LifecyclePhase, reason: BlockedReason?,
                             gateOpen: Bool, captureSessionLive: Bool) -> String {
        // Only phases that assert active collection need a live-session witness;
        // paused/stopped/unstarted legitimately have none.
        let claimsCollecting = phase == .collecting
        let sessionMissing = claimsCollecting && !captureSessionLive
        if !gateOpen || phase == .blocked || sessionMissing {
            if let reason { return "BLOCKED — \(reason)" }
            // Distinguish the two no-reason causes. Saying "locked" when the real problem
            // is a dead capture session points the user at the wrong remedy.
            return sessionMissing ? "BLOCKED — capture not running" : "BLOCKED — locked"
        }
        switch phase {
        case .collecting: return "● Collecting"
        case .paused: return "❚❚ Paused"
        case .stopped: return "■ Stopped"
        case .unstarted, .consent: return "Not started"
        default: return String(describing: phase).capitalized
        }
    }
}
