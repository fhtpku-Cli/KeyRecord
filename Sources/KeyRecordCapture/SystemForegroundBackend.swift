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
public final class CaptureWorkspaceFence {
    private var observers: [any NSObjectProtocol] = []

    public init(queue: CaptureQueue) {
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: nil) { _ in queue.revoke() })
        }
    }

    public func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
