import AppKit
import KeyRecordCore

@MainActor
public final class SystemForegroundProvider: FrontmostAppProvider {
    public init() {}

    public func foregroundState() async -> ForegroundState {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        guard !app.isTerminated else { return .unknown }
        return ForegroundReading.observed(bundleID: app.bundleIdentifier).state
    }
}

@MainActor
final class CaptureWorkspaceFence {
    private var observers: [any NSObjectProtocol] = []

    init(invalidate: @escaping @Sendable (CaptureInvalidation) -> Void) {
        for (name, reason) in [
            (NSWorkspace.didActivateApplicationNotification, CaptureInvalidation.foregroundChanged),
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionChanged)
        ] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: nil) { _ in invalidate(reason) })
        }
    }

    func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
