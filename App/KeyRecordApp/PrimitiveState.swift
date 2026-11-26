import KeyRecordCore
import SwiftUI

enum PrimitiveState: String, CaseIterable {
    case unstarted, paused, collecting, blocked, error

    var statusKey: String { "status.\(rawValue)" }
    var symbol: String {
        switch self {
        case .unstarted: "circle"
        case .paused: "pause.circle"
        case .collecting: "record.circle"
        case .blocked: "lock.circle"
        case .error: "exclamationmark.triangle"
        }
    }
    var actionKey: String {
        switch self {
        case .unstarted: "action.start"
        case .paused: "action.resume"
        case .collecting: "action.pause"
        case .blocked: "action.settings"
        case .error: "action.retry"
        }
    }
}

struct PrimitiveFixture {
    let state: PrimitiveState
    let locale: String
    let dark: Bool
    let stress: Bool
    var empty = false
}

@MainActor
final class HarnessSelection: ObservableObject {
    @Published var locale: String {
        didSet { titleChanged(windowTitle) }
    }
    private let titleChanged: (String) -> Void
    var windowTitle: String { NativeText(locale: locale)("harness.title") }
    init(locale: String, titleChanged: @escaping (String) -> Void) {
        self.locale = locale
        self.titleChanged = titleChanged
    }
}

final class ResourceAnchor {}

struct NativeText {
    let locale: String
    func callAsFunction(_ key: String) -> String {
        let resources = Bundle(for: ResourceAnchor.self)
        guard let path = resources.path(forResource: locale, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
    func aggregateName(_ value: String) -> String {
        value.isEmpty ? self("aggregate.empty") : value
    }
}

extension NativeText {
    func captureStatus(_ status: CaptureStatusPresentation.Status) -> String {
        switch status {
        case .blocked(.keyUnavailable): return self("capture.keyUnavailable")
        case .blocked(.sessionLocked): return self("capture.sessionLocked")
        case .blocked(.secureInputActive): return self("capture.secureInputActive")
        case .blocked(.foregroundUnreliable): return self("capture.foregroundUnreliable")
        case .blocked(.privacyCheckRequired), .phase(.blocked): return self("status.blocked")
        case .missingSession: return self("capture.missingSession")
        case .locked: return self("capture.locked")
        case .phase(.unstarted), .phase(.consent): return self("status.unstarted")
        case .phase(.starting): return self("capture.starting")
        case .phase(.collecting): return self("status.collecting")
        case .phase(.pausing): return self("capture.pausing")
        case .phase(.paused): return self("status.paused")
        case .phase(.resuming): return self("capture.resuming")
        case .phase(.stopping): return self("capture.stopping")
        case .phase(.stopped): return self("capture.stopped")
        case .phase(.reopening): return self("capture.reopening")
        case .phase(.failed): return self("capture.failed")
        }
    }
}
