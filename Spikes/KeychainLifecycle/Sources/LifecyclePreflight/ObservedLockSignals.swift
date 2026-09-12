import AppKit

public enum ObservedLockSignals {
    public enum Center { case workspace, distributed }
    public static let qualifiedLiveVersions: Set<String> = []

    // SDK AppKit.framework/Headers/NSWorkspace.h:33-34,322-330; also
    // developer.apple.com/documentation/appkit/nsworkspace/notificationcenter
    // verifies workspace delivery, NOT screen-unlock authority. Compile range: macOS 14+.
    // com.apple.screenIsLocked/Unlocked are observed names, not a public API guarantee.
    // Live support envelope is empty until exact OS/build + controller observations qualify it.
    public static func map(_ name: Notification.Name, center: Center) -> LockSignal? {
        switch center {
        case .workspace:
            switch name {
            case NSWorkspace.sessionDidResignActiveNotification: .sessionResigned
            case NSWorkspace.sessionDidBecomeActiveNotification: .sessionBecameActive
            case NSWorkspace.willSleepNotification: .willSleep
            case NSWorkspace.didWakeNotification: .didWake
            default: nil
            }
        case .distributed:
            switch name.rawValue {
            case "com.apple.screenIsLocked": .screenLocked
            case "com.apple.screenIsUnlocked": .screenUnlocked
            default: nil
            }
        }
    }
}
