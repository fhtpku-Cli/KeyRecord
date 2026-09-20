import AppKit
import KeyRecordCore

/// A running ordinary GUI application, reduced to what the exclusions picker needs.
struct RunningAppDescriptor: Sendable, Equatable {
    let bundleID: String
    let name: String
}

/// Source of exclusion candidates for the settings screen (KR-04).
///
/// Scope is deliberately minimal: applications that are *currently running* as ordinary
/// GUI apps, plus bundle ids the user has already excluded even when those are not
/// running right now. This is not a whole-disk application index, and it performs no
/// filesystem scan.
@MainActor
protocol ExclusionCandidateSource {
    /// Returns running regular GUI applications. Throws if enumeration genuinely fails, so
    /// the UI can distinguish "no candidates" from "could not read candidates".
    func runningApplications() throws -> [RunningAppDescriptor]
}

enum ExclusionCandidateError: Error, Equatable { case enumerationFailed }

@MainActor
struct WorkspaceExclusionCandidates: ExclusionCandidateSource {
    func runningApplications() throws -> [RunningAppDescriptor] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            // `.regular` excludes agents, daemons and accessory processes: only apps the
            // user can actually type into are meaningful exclusion targets.
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
            let name = app.localizedName ?? bundleID
            return RunningAppDescriptor(bundleID: bundleID, name: name)
        }
    }
}

/// Pure merge step, kept free of AppKit so it is directly unit-testable.
///
/// Rules:
/// * de-duplicate by bundle id (a running app already saved as excluded appears once);
/// * saved-but-not-running exclusions remain visible so they can always be un-excluded;
/// * the current foreground app is flagged;
/// * ordering is by display name, case- and locale-insensitively, with bundle id as a
///   stable tiebreaker so the list never reorders between refreshes.
enum ExclusionChoiceMerge {
    static func choices(running: [RunningAppDescriptor],
                        excluded: Set<String>,
                        foregroundBundleID: String?) -> [AppChoice] {
        var byBundle: [String: String] = [:]
        for app in running where byBundle[app.bundleID] == nil {
            byBundle[app.bundleID] = app.name
        }
        // Saved exclusions stay listed even when the app is not running; without a running
        // instance there is no localized name, so the bundle id is shown instead.
        for bundleID in excluded where byBundle[bundleID] == nil {
            byBundle[bundleID] = bundleID
        }
        return byBundle
            .map { bundleID, name in
                AppChoice(bundleID: bundleID, name: name,
                          isExcluded: excluded.contains(bundleID),
                          isForeground: bundleID == foregroundBundleID)
            }
            .sorted {
                let left = $0.name.localizedCaseInsensitiveCompare($1.name)
                if left != .orderedSame { return left == .orderedAscending }
                return $0.bundleID < $1.bundleID
            }
    }
}
