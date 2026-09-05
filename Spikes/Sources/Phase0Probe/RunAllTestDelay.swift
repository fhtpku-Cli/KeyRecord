import Foundation

enum RunAllTestDelay {
    static func wait(environmentKey: String, cleanup: RunAllSignalCleanup) throws {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey], let delay = Double(raw) else { return }
        if let path = ProcessInfo.processInfo.environment["KEYRECORD_RUN_ALL_TEST_READY_FILE"] {
            try Data().write(to: URL(fileURLWithPath: path))
        }
        Thread.sleep(forTimeInterval: min(max(delay, 0), 5))
        try cleanup.throwIfInterrupted()
    }
}
