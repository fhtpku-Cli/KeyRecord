import AppKit
import SwiftUI
import KeyRecordCore

@MainActor
struct UpdatePorts {
    var currentVersion: String
    var now: () -> Date = { Date() }
    var lastAttempt: () -> Date? = { nil }
    var saveAttempt: (Date) -> Void = { _ in }
    var clearAttempt: () -> Void = {}
    var fetch: @Sendable () async throws -> Data?
    var open: (URL) -> Bool = { _ in false }
    static func system() -> Self {
        Self(currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
             lastAttempt: { UserDefaults.standard.object(forKey: "KeyRecord.lastUpdateAttempt") as? Date },
             saveAttempt: { UserDefaults.standard.set($0, forKey: "KeyRecord.lastUpdateAttempt") },
             clearAttempt: { UserDefaults.standard.removeObject(forKey: "KeyRecord.lastUpdateAttempt") },
             fetch: { try await UpdateHTTPClient.fetch() }, open: { NSWorkspace.shared.open($0) })
    }
}

@MainActor
final class UpdatesModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message = "updates.idle"
    @Published private(set) var available: AvailableRelease?
    @Published private(set) var currentVersion = ""
    @Published private(set) var lastAttempt: Date?
    @Published var reviewing = false
    private var ports: UpdatePorts?
    private var scheduled: Task<Void, Never>?
    private var request: Task<Data?, Error>?
    private var session = UUID()
    func configure(_ ports: UpdatePorts) {
        stop(); self.ports = ports; currentVersion = ports.currentVersion; lastAttempt = ports.lastAttempt()
    }
    func start() {
        guard scheduled == nil, ports != nil else { return }
        scheduled = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(manual: false)
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }
    func stop() { scheduled?.cancel(); scheduled = nil; cancel() }
    func eraseHistory() { stop(); ports?.clearAttempt(); lastAttempt = nil }
    func cancel() {
        session = UUID(); request?.cancel(); request = nil; busy = false; reviewing = false
        available = nil; message = "updates.idle"
    }
    func check(manual: Bool) async {
        guard !busy, let ports else { return }
        let now = ports.now()
        guard manual || ReleaseUpdate.isDue(now: now, lastAttempt: ports.lastAttempt()) else { return }
        guard let current = ReleaseVersion(currentVersion) else { message = "updates.invalidVersion"; return }
        session = UUID(); let ticket = session
        busy = true; available = nil; reviewing = false; message = "updates.checking"
        ports.saveAttempt(now); lastAttempt = now
        let fetch = Task { try await ports.fetch() }; request = fetch
        defer { if ticket == session { busy = false; request = nil } }
        do {
            let data = try await fetch.value
            guard ticket == session, !Task.isCancelled else { return }
            guard let data else { message = "updates.noRelease"; return }
            let release = try ReleaseUpdate.parse(data)
            if release.version > current { available = release; message = "updates.available" }
            else { message = "updates.current" }
        } catch { if ticket == session { message = "updates.failed" } }
    }
    func requestReview() { if !busy, available != nil { reviewing = true } }
    func confirmOpen() {
        guard reviewing, !busy, let release = available, let ports,
              let url = URL(string: UpdateHTTPClient.releasePrefix + release.tag) else { return }
        reviewing = false
        if !ports.open(url) { message = "updates.openFailed" }
    }
}

struct UpdatesSection: View {
    @ObservedObject var model: UpdatesModel
    let text: NativeText
    var body: some View {
        Section {
            Text(text("updates.notice")).fixedSize(horizontal: false, vertical: true)
            Text(text("updates.version") + ": " + model.currentVersion)
            Text(text(model.message)).accessibilityIdentifier("updates.status")
            if let date = model.lastAttempt { HStack { Text(text("updates.lastAttempt")); Text(date, style: .date) } }
            Button(text("updates.check")) { Task { await model.check(manual: true) } }
                .disabled(model.busy).accessibilityIdentifier("updates.check")
            if model.busy { Button(text("action.cancel")) { model.cancel() }.accessibilityIdentifier("updates.cancel") }
            if let release = model.available {
                Text(release.tag)
                Button(text("updates.review")) { model.requestReview() }.accessibilityIdentifier("updates.review")
            }
        } header: { Text(text("updates.title")) }
        .sheet(isPresented: $model.reviewing) {
            VStack(alignment: .leading, spacing: 16) {
                Text(text("updates.confirm")).font(.headline)
                Text(text("updates.manualInstall"))
                Button(text("updates.open")) { model.confirmOpen() }.accessibilityIdentifier("updates.open")
                Button(text("action.cancel")) { model.reviewing = false }.keyboardShortcut(.cancelAction)
            }.padding().frame(width: 420)
        }
    }
}
