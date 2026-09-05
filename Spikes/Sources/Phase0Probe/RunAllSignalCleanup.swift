import Darwin
import Foundation

struct RunAllInterruption: Error {
    let status: Int32
}

final class RunAllSignalCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Int32?
    private var interruptionStatus: Int32?
    private var sources: [DispatchSourceSignal] = []

    init(paths _: [URL]) {
        for item in [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] {
            signal(item.0, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: item.0, queue: .global())
            source.setEventHandler { [weak self] in self?.interrupt(status: Int32(item.1)) }
            source.resume()
            sources.append(source)
        }
    }

    func setChild(_ pid: Int32?) {
        lock.lock()
        child = pid
        let interrupted = interruptionStatus != nil
        lock.unlock()
        if interrupted, let pid { Darwin.kill(pid, SIGTERM) }
    }

    func throwIfInterrupted() throws {
        lock.lock()
        let status = interruptionStatus
        lock.unlock()
        if let status { throw RunAllInterruption(status: status) }
    }

    func complete() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
        signal(SIGHUP, SIG_DFL)
    }

    private func interrupt(status: Int32) {
        lock.lock()
        if interruptionStatus == nil { interruptionStatus = status }
        let pid = child
        lock.unlock()
        if let pid { Darwin.kill(pid, SIGTERM) }
    }
}
