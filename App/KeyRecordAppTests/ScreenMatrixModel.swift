import AppKit
import SwiftUI
import KeyRecordCore

// MARK: - Task 22 matrix axes (PRD FR-U3/U4, DESIGN §§2-7)

/// The six rendered states: the five task-10 status words plus the consent phase,
/// which presents the same unstarted status word but a distinct screen.
enum MatrixState: String, CaseIterable {
    case unstarted, consent, paused, collecting, blocked, error

    var phase: LifecyclePhase {
        switch self {
        case .unstarted: return .unstarted
        case .consent: return .consent
        case .paused: return .paused
        case .collecting: return .collecting
        case .blocked: return .blocked
        case .error: return .failed
        }
    }

    /// Sensitive aggregate content is visible only in the two steady usage phases.
    var showsAggregates: Bool { self == .paused || self == .collecting }
}

enum MatrixAppearance: String, CaseIterable {
    case light, dark, highContrastLight, highContrastDark

    var name: NSAppearance.Name {
        switch self {
        case .light: return .aqua
        case .dark: return .darkAqua
        case .highContrastLight: return .accessibilityHighContrastAqua
        case .highContrastDark: return .accessibilityHighContrastDarkAqua
        }
    }
    var dark: Bool { self == .dark || self == .highContrastDark }
    var highContrast: Bool { self == .highContrastLight || self == .highContrastDark }
    var stem: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        case .highContrastLight: return "hc-light"
        case .highContrastDark: return "hc-dark"
        }
    }
}

struct MatrixFixture {
    let state: MatrixState
    let locale: String
    let appearance: MatrixAppearance
    var reduceMotion = false
    var stress = false
    var largeType = false
    var emptyChoices = false
    var size = NativeLayout.aggregateMinimum

    /// Filename stem carrying locale-appearance-motion-state as the evidence contract requires.
    var stem: String {
        "\(locale)-\(appearance.stem)-\(reduceMotion ? "reduce" : "normal")-\(state.rawValue)"
    }
}

/// Screens rendered for the matrix. Raw values double as filename components.
enum ScreenKind: String, CaseIterable {
    case consent, menu, settings, aggregate, aggregateEmpty, aggregateLocked
    case dialogReset, dialogDelete

    /// AX identifiers that must resolve exactly once (rows repeat and are checked separately).
    var uniqueIDs: [String] {
        switch self {
        case .consent: return ["consent.panel", "consent.disclosure", "consent.accept", "consent.reject"]
        case .menu: return ["capture.symbol", "capture.status", "menu.start", "menu.pause",
                            "menu.resume", "menu.settings", "menu.quit"]
        case .settings: return ["settings.form", "settings.login", "settings.language",
                                "settings.reset", "settings.delete"]
        case .aggregate: return ["aggregates.panel", "aggregates.shortcutTotal",
                                 "aggregates.bareTotal", "aggregates.list"]
        case .aggregateEmpty: return ["aggregates.panel", "aggregates.empty"]
        case .aggregateLocked: return ["aggregates.panel", "aggregates.locked"]
        case .dialogReset, .dialogDelete: return ["dialog.panel", "dialog.message",
                                                  "dialog.confirm", "dialog.cancel"]
        }
    }

    /// Interactive (keyboard/AX-activatable) element identifiers per screen.
    var interactiveIDs: [String] {
        switch self {
        case .consent: return ["consent.accept", "consent.reject"]
        case .menu: return ["menu.start", "menu.pause", "menu.resume", "menu.settings", "menu.quit"]
        case .settings: return ["settings.login", "settings.language", "settings.reset", "settings.delete"]
        case .dialogReset, .dialogDelete: return ["dialog.cancel", "dialog.confirm"]
        case .aggregate, .aggregateEmpty, .aggregateLocked: return []
        }
    }
}

// MARK: - Deterministic fixture content

enum MatrixContent {
    static let locales = ["en", "zh-Hans"]

    static func menuFrame(anchor: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGRect {
        CGRect(x: min(max(anchor.x, visibleFrame.minX), visibleFrame.maxX - size.width),
               y: min(max(anchor.y - size.height, visibleFrame.minY), visibleFrame.maxY - size.height),
               width: size.width, height: size.height)
    }

    static func lifecycleState(for state: MatrixState) -> LifecycleState {
        switch state {
        case .unstarted:
            return LifecycleState(phase: .unstarted)
        case .consent:
            return LifecycleState(phase: .consent)
        case .paused:
            var gate = PrivacyGate()
            gate.update(GateInputs(collecting: false, keyAvailability: .available,
                                   sessionLock: .unlocked, secureInput: .disabled,
                                   foreground: .attributable(bundleID: "com.example.editor"),
                                   exclusion: .included))
            return LifecycleState(phase: .paused,
                conditions: RuntimeConditions(keyAvailability: .available, sessionLock: .unlocked,
                    secureInput: .disabled, foreground: .attributable(bundleID: "com.example.editor")), gate: gate)
        case .collecting:
            var gate = PrivacyGate()
            gate.update(GateInputs(collecting: true, keyAvailability: .available,
                                   sessionLock: .unlocked, secureInput: .disabled,
                                   foreground: .attributable(bundleID: "com.example.editor"),
                                   exclusion: .included))
            return LifecycleState(phase: .collecting, gate: gate)
        case .blocked:
            return LifecycleState(phase: .blocked, blockedReason: .sessionLocked)
        case .error:
            return LifecycleState(phase: .failed)
        }
    }

    /// Rows cover unknown/stateful/system classifications, ordinary/suspected/unknown
    /// source confidence, unknown app bucket, bare keys and (under stress) long CJK
    /// app names plus large totals. All synthetic; no real keystroke data.
    static func snapshot(stress: Bool) -> AggregateSnapshot {
        func modifiers(_ command: ModifierSideState, _ shift: ModifierSideState) -> ModifierSet {
            ModifierSet(command: command, option: .none, control: .none, shift: shift, fn: .none)
        }
        func bucket(_ code: Int, _ modifiers: ModifierSet, _ app: AppBucket) -> ChordBucket {
            // swiftlint:disable:next force_try - matrix codes are valid HIToolbox constants
            ChordBucket(chord: Chord(keyCode: try! KeyCode(code), modifiers: modifiers), appBucket: app)
        }
        let longApp = "com.example.一个非常长的应用程序名称用来验证换行与裁剪行为是否会导致关键内容丢失"
        let rows = [
            KeyRecordCore.AggregateRow(identity: .shortcut(bucket(48, modifiers(.both, .none), .unknown)),
                         total: stress ? 987_654 : 12, classification: .discrete,
                         sourceConfidence: .ordinary),
            KeyRecordCore.AggregateRow(identity: .shortcut(bucket(20, modifiers(.both, .both),
                             .bundleID(stress ? longApp : "com.example.editor"))),
                         total: stress ? 12_345 : 3, classification: .stateful,
                         sourceConfidence: .suspectedInjection),
            KeyRecordCore.AggregateRow(identity: .shortcut(bucket(8, modifiers(.both, .none),
                             .bundleID("com.example.chat"))),
                         total: 5, classification: .system, sourceConfidence: .unknown),
            // swiftlint:disable:next force_try - matrix codes are valid HIToolbox constants
            KeyRecordCore.AggregateRow(identity: .bareKey(try! KeyCode(99)), total: stress ? 65_432 : 7,
                         classification: .discrete, sourceConfidence: .ordinary),
        ]
        return try! AggregateSnapshot(rows: rows)
    }

    /// Exclusion-picker rows; stress uses long CJK display names (synthetic user data).
    static func choices(stress: Bool) -> [AppChoice] {
        let editor = stress ? String(repeating: "示例编辑器·", count: 12) : "Example Editor"
        let chat = stress ? String(repeating: "示例聊天应用·", count: 10) : "Example Chat"
        return [
            AppChoice(bundleID: "com.example.editor", name: editor, isExcluded: false, isForeground: true),
            AppChoice(bundleID: "com.example.chat", name: chat, isExcluded: true, isForeground: false),
        ]
    }
}

// MARK: - Lifecycle driver + action journal

@MainActor
final class MatrixDriver: LifecycleDriving {
    var state: LifecycleState
    init(state: LifecycleState) { self.state = state }
    func returnToConsentRequired() async { state = .initial }
}

@MainActor
final class MatrixJournal {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func reset() { events.removeAll() }
}
