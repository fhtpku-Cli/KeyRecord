import AppKit
import ApplicationServices
import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis
import KeyRecordStore

enum MenuShortcutReadError: Error { case unavailable, limit }

struct MenuApplicationTarget: Equatable, Sendable {
    let bundleID: String
    let pid: Int32
    let launchedAt: Date
}

enum MenuShortcutScan {
    static func read<Node>(root: Node, check: () throws -> Void,
                           children: (Node) throws -> [Node], shortcut: (Node) throws -> Chord?) throws -> Set<Chord> {
        var pending = [(root, 0)], count = 0
        var result: Set<Chord> = []
        while let (node, depth) = pending.popLast() {
            try check()
            count += 1
            guard count <= 2048, depth <= 16 else { throw MenuShortcutReadError.limit }
            if let chord = try shortcut(node) { result.insert(chord) }
            let next = try children(node)
            guard next.count + pending.count + count <= 2048 else { throw MenuShortcutReadError.limit }
            pending += next.map { ($0, depth + 1) }
        }
        return result
    }
}

struct MenuShortcutPorts: Sendable {
    var resolve: @MainActor @Sendable (String) -> MenuApplicationTarget? = { bundleID in
        guard AXIsProcessTrusted() else { return nil }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
        guard apps.count == 1, let app = apps.first, let date = app.launchDate else { return nil }
        return MenuApplicationTarget(bundleID: bundleID, pid: app.processIdentifier, launchedAt: date)
    }
    var read: @Sendable (MenuApplicationTarget, @Sendable () throws -> Void) throws -> Set<Chord> = { target, allowed in
        guard AXIsProcessTrusted() else { throw MenuShortcutReadError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        func check() throws {
            try allowed(); try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw MenuShortcutReadError.limit }
        }
        func attribute(_ node: AXUIElement, _ name: String) throws -> CFTypeRef? {
            try check()
            guard AXUIElementSetMessagingTimeout(node, 0.1) == .success else { throw MenuShortcutReadError.unavailable }
            var value: CFTypeRef?
            switch AXUIElementCopyAttributeValue(node, name as CFString, &value) {
            case .success: return value
            case .noValue, .attributeUnsupported: return nil
            default: throw MenuShortcutReadError.unavailable
            }
        }
        let app = AXUIElementCreateApplication(target.pid)
        guard let raw = try attribute(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw MenuShortcutReadError.unavailable
        }
        let root = raw as! AXUIElement
        return try MenuShortcutScan.read(root: root, check: check, children: { node in
            guard let role = try attribute(node, kAXRoleAttribute) as? String,
                  [kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuRole, kAXMenuItemRole].contains(role) else { return [] }
            try check()
            var count = 0
            let status = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
            if status == .noValue || status == .attributeUnsupported { return [] }
            guard status == .success, count >= 0, count <= 2048 else { throw MenuShortcutReadError.limit }
            if count == 0 { return [] }
            var children: CFArray?
            try check()
            guard AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, count, &children) == .success,
                  let values = children as? [AXUIElement], values.count == count else { throw MenuShortcutReadError.unavailable }
            return values
        }, shortcut: { node in
            guard try attribute(node, kAXRoleAttribute) as? String == kAXMenuItemRole,
                  let key = try attribute(node, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber,
                  let modifiers = try attribute(node, kAXMenuItemCmdModifiersAttribute) as? NSNumber,
                  CFGetTypeID(key) == CFNumberGetTypeID(), CFGetTypeID(modifiers) == CFNumberGetTypeID(),
                  key.doubleValue == Double(key.intValue), modifiers.doubleValue == Double(modifiers.intValue) else { return nil }
            return MenuShortcutEvidence.chord(virtualKey: key.intValue, modifiers: modifiers.intValue)
        })
    }
}

@MainActor
final class MenuShortcutsModel: ObservableObject {
    @Published var application = "" { didSet { if oldValue != application { clear() } } }
    @Published private(set) var working = false
    @Published private(set) var issueKey: String?
    private var observation: (MenuApplicationTarget, MenuShortcutEvidence, CaptureGeneration)?
    var ports = MenuShortcutPorts()
    var gate: KeyAvailabilityGate?
    var canRead: @MainActor () -> Bool = { false }
    var onChange: @MainActor () -> Void = {}
    private var session = UUID()
    private var task: Task<Set<Chord>, Error>?
    var evidence: MenuShortcutEvidence? {
        guard canRead(), let gate, let (target, value, generation) = observation, application == target.bundleID,
              ports.resolve(application) == target, (try? gate.check(generation)) != nil else { return nil }
        return value
    }
    func clear() {
        session = UUID(); task?.cancel(); task = nil
        observation = nil; issueKey = nil; working = false; onChange()
    }
    func reset() {
        if application.isEmpty { clear() } else { application = "" }
    }
    func refresh() async {
        guard canRead(), !working, let gate else { return }
        clear()
        guard let target = ports.resolve(application), let generation = try? gate.begin() else {
            issueKey = "menuShortcuts.unavailable"; return
        }
        working = true
        let ticket = session, reader = ports.read
        let request = Task.detached { try reader(target) { try gate.check(generation) } }
        task = request
        defer { if ticket == session { working = false; task = nil; onChange() } }
        do {
            let shortcuts = try await request.value
            guard ticket == session, canRead() else { return }
            guard ports.resolve(application) == target else { issueKey = "menuShortcuts.unavailable"; return }
            observation = try gate.use(generation) { (target, .init(application: target.bundleID, shortcuts: shortcuts), generation) }
            issueKey = "menuShortcuts.partial"
        } catch { if ticket == session, canRead() { issueKey = "menuShortcuts.unavailable" } }
    }
}

struct MenuShortcutsSection: View {
    @ObservedObject var model: MenuShortcutsModel
    let choices: [AppChoice]
    let text: NativeText
    var body: some View {
        Section {
            Text(text("menuShortcuts.notice")).fixedSize(horizontal: false, vertical: true)
            Picker(text("menuShortcuts.application"), selection: $model.application) {
                Text(text("menuShortcuts.choose")).tag("")
                ForEach(choices.filter { !$0.isExcluded }) { Text($0.name).tag($0.bundleID) }
            }.accessibilityIdentifier("menuShortcuts.application")
            Button(text("menuShortcuts.read")) { Task { await model.refresh() } }
                .disabled(model.working || model.application.isEmpty).accessibilityIdentifier("menuShortcuts.read")
            if model.working {
                Button(text("action.cancel")) { model.clear() }.accessibilityIdentifier("menuShortcuts.cancel")
            }
            if let issue = model.issueKey {
                Text(text(issue == "menuShortcuts.partial" && model.evidence == nil ? "menuShortcuts.unavailable" : issue))
                    .accessibilityIdentifier("menuShortcuts.status")
            }
        } header: { Text(text("menuShortcuts.title")) }
    }
}
