import Foundation

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
