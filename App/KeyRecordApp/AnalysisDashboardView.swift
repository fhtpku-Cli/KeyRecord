import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

private enum AnalysisRoute: Hashable {
    case overview
    case shortcuts
    case applications
    case allCandidates
    case bareKeys
    case shortcut(String)
    case candidate(String)
}

struct AnalysisLayoutControls: View {
    let layout: LayoutPreference
    let ask: Bool
    let text: NativeText
    let noticeKey: String?
    let saveLayout: @MainActor (LayoutPreset) async -> Void
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            if ask {
                Text(text("phase2.layoutQuestion")).accessibilityIdentifier("phase2.layout.question")
            }
            Text(String(format: text("phase2.layoutCurrent"), AnalysisLabels.layout(layout.preset, text: text)))
            if let noticeKey { Text(text(noticeKey)).font(.caption).accessibilityIdentifier("phase2.preferenceNotice") }
            HStack(spacing: NativeLayout.compact) {
                ForEach([LayoutPreset.ansi, .iso, .alice, .split, .none], id: \.rawValue) { preset in
                    NativeAction(title: AnalysisLabels.layout(preset, text: text),
                                 identifier: "phase2.layout.\(preset.rawValue)") {
                        saving = true
                        Task { @MainActor in
                            await saveLayout(preset)
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            Text(text("phase2.layoutNote")).font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnalysisDashboardView: View {
    let snapshot: AnalysisSnapshot?
    var fallbackAggregate: AggregateSnapshot? = nil
    let layout: LayoutPreference
    var ignoredKeys: Set<String> = []
    var keyboardPool: Set<KeyCode> = []
    var backend: BackendConnection = .disconnected(.karabiner)
    var createMapping: (@MainActor (Chord, Chord, RecommendationScope) -> Void)?
    var physicalEvidence: PhysicalEvidence?
    var viaReference: VIAImportedConfiguration?
    var conflictEvidence: CandidateConflictEvidence?
    let text: NativeText
    var statusKey: String? = nil
    var captureStatus: CaptureStatusPresentation.Status?
    var analysisUnavailable = false
    var preferenceNoticeKey: String?
    var canUndoIgnore = false
    let saveLayout: @MainActor (LayoutPreset) async -> Void
    var ignore: @MainActor (String) async -> Void = { _ in }
    var restore: @MainActor (String) async -> Void = { _ in }
    var undoIgnore: @MainActor () async -> Void = {}
    var openCandidates: (() -> Void)?
    var showsLayoutControls = true
    var surface: AnalysisSurface = .both

    @State private var route: AnalysisRoute = .overview
    @State private var history: [(AnalysisRoute, String)] = []
    @State private var returnFocus: String?
    @FocusState private var focusedControl: String?
    @AccessibilityFocusState private var accessibilityFocus: String?

    var body: some View {
        Group {
            if snapshot == nil && fallbackAggregate == nil {
                locked
            } else if route == .overview || snapshot == nil {
                overview
            } else {
                detail
            }
        }
        .onChange(of: snapshot?.cycleID) { _, _ in
            history.removeAll()
            route = .overview
            returnFocus = nil
        }
        .onExitCommand { if route != .overview { closeDetail() } }
        .onChange(of: route) { _, _ in
            focusedControl = returnFocus ?? "phase2.back"
            accessibilityFocus = focusedControl
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let captureStatus {
            Text(text.captureStatus(captureStatus)).foregroundStyle(.secondary)
        } else if let statusKey {
            Text(text(statusKey)).foregroundStyle(.secondary)
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: NativeLayout.group) {
            Label(text("overview.hidden"), systemImage: "lock.circle").font(.title2)
            statusLine
            if captureStatus == .blocked(.secureInputActive) {
                Text(text("overview.leaveSecureInput"))
            } else {
                Text(text("aggregate.locked")).foregroundStyle(.secondary)
            }
        }
        .padding(NativeLayout.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("phase2.locked")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NativeLayout.group) {
                if surface != .candidates {
                    Text(text("phase2.title")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    statusLine
                    if let snapshot {
                        let groups = AnalysisStatisticGroup.make(snapshot)
                        if groups.isEmpty && snapshot.bareKeys.isEmpty {
                            Text(text("phase2.emptyCycle"))
                        } else {
                            shortcutColumn(groups, limit: AnalysisOverviewLimits.shortcuts)
                            recommendations(snapshot)
                            HStack {
                                routeButton("phase2.applications", .applications, "phase2.open.applications")
                                routeButton("phase2.bare", .bareKeys, "phase2.open.bare")
                            }
                        }
                        if showsLayoutControls {
                            AnalysisLayoutControls(layout: layout, ask: snapshot.shouldAskLayout && !layout.hasAsked,
                                text: text, noticeKey: preferenceNoticeKey, saveLayout: saveLayout)
                        }
                    } else if let fallbackAggregate {
                        if analysisUnavailable {
                            Text(text("phase2.analysisUnavailable")).accessibilityIdentifier("phase2.analysisUnavailable")
                        }
                        totals(shortcutTotal: fallbackAggregate.shortcutTotal, bareTotal: fallbackAggregate.bareKeyTotal, activeDays: nil)
                        Text(text("phase2.fallbackTotals")).font(.caption)
                    }
                }
                if surface != .overview, let snapshot {
                    candidatesPage(snapshot)
                }
            }
            .padding(NativeLayout.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("phase2.dashboard")
    }

    private func routeButton(_ key: String, _ destination: AnalysisRoute, _ identifier: String) -> some View {
        Button(text(key)) { open(destination, focus: identifier) }
            .focused($focusedControl, equals: identifier)
            .accessibilityFocused($accessibilityFocus, equals: identifier)
            .accessibilityIdentifier(identifier)
    }

    private func totals(shortcutTotal: Int64, bareTotal: Int64, activeDays: Int?) -> some View {
        HStack(spacing: NativeLayout.group) {
            Text(String(format: text("aggregate.totalShortcuts"), shortcutTotal))
            Text(String(format: text("aggregate.totalBare"), bareTotal))
            if let activeDays {
                Text(String(format: text("phase2.activeDays"), activeDays))
            }
        }
    }

    private func shortcutColumn(_ groups: [AnalysisStatisticGroup], limit: Int?) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                if groups.isEmpty { Text(text("phase2.shortcutsEmpty")) }
                ForEach(Array(groups.prefix(limit ?? groups.count))) { group in
                    let identifier = "phase2.detail.\(group.id)"
                    Button {
                        open(.shortcut(group.id), focus: identifier)
                    } label: {
                        HStack(spacing: NativeLayout.group) {
                            Text(AnalysisLabels.compactChord(group.representative, text: text)).font(.headline)
                            Spacer()
                            ProgressView(value: Double(group.total), total: Double(max(1, groups.first?.total ?? 1)))
                                .frame(maxWidth: 160).accessibilityHidden(true)
                            Text(String(format: text("overview.uses"), group.total)).monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedControl, equals: identifier)
                    .accessibilityFocused($accessibilityFocus, equals: identifier)
                    .accessibilityLabel(AnalysisLabels.chord(group.representative, text: text))
                    .accessibilityValue(String(format: text("overview.uses"), group.total))
                    .accessibilityIdentifier(identifier)
                }
                if let limit, groups.count > limit {
                    routeButton("phase2.viewAll", .shortcuts, "phase2.open.shortcuts")
                }
            }.padding(NativeLayout.compact).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.shortcuts")).font(.headline) }
    }

    private func applicationColumn(_ snapshot: AnalysisSnapshot, total: Int64) -> some View {
        let rows = snapshot.applications
        return GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text("phase2.appShare")).font(.caption)
                if snapshot.applications.isEmpty { Text(text("aggregate.emptyState")) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading) {
                        Text(AnalysisLabels.app(row.app, text: text))
                        Text(shareLine(row.sourceCounts.total.value, total: total))
                    }.accessibilityIdentifier("phase2.stat.application")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.applications")) }
    }

    private func bareColumn(_ snapshot: AnalysisSnapshot) -> some View {
        let rows = snapshot.bareKeys
        let peak = snapshot.bareKeys.map(\.sourceCounts.total.value).max() ?? 1
        return GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text("phase2.bareNote")).font(.caption)
                if snapshot.bareKeys.isEmpty { Text(text("phase2.bareEmpty")) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: NativeLayout.page * 8))], alignment: .leading, spacing: NativeLayout.group) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let count = row.sourceCounts.total.value
                        VStack(alignment: .leading, spacing: NativeLayout.compact) {
                            Text(AnalysisLabels.key(row.keyCode, text: text)).font(.headline)
                            Text(String(format: text("phase2.rawUses"), count))
                            ProgressView(value: Double(count), total: Double(max(1, peak)))
                                .accessibilityLabel(AnalysisLabels.key(row.keyCode, text: text))
                                .accessibilityValue(String(format: text("phase2.intensityValue"), count))
                        }.accessibilityIdentifier("phase2.stat.bare")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.bare")) }
    }

    private func recommendations(_ snapshot: AnalysisSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                if let candidate = snapshot.topRecommendations.first {
                    let identifier = "phase2.candidateOpen.\(candidate.id)"
                    Button {
                        open(.candidate(candidate.id), focus: identifier)
                    } label: {
                        Text(String(format: text("overview.suggestion"),
                                    AnalysisLabels.compactChord(candidate.chord, text: text),
                                    candidate.factors.savedPerUse))
                    }
                    .focused($focusedControl, equals: identifier)
                    .accessibilityFocused($accessibilityFocus, equals: identifier)
                    .accessibilityIdentifier(identifier)
                }
                if snapshot.topRecommendations.isEmpty {
                    Text(text(snapshot.candidates.contains { $0.status == .eligible } ? "phase2.noPositive" : "phase2.noEligible"))
                        .foregroundStyle(.secondary)
                }
                let remaining = max(0, snapshot.topRecommendations.count - 1)
                let moreTitle = remaining > 0
                    ? String(format: text("overview.moreSuggestions"), remaining) : text("phase2.showAll")
                Button(moreTitle) {
                    if let openCandidates { openCandidates() }
                    else { open(.allCandidates, focus: "phase2.showAll") }
                }
                .focused($focusedControl, equals: "phase2.showAll")
                .accessibilityFocused($accessibilityFocus, equals: "phase2.showAll")
                .accessibilityIdentifier("phase2.showAll")
                if let preferenceNoticeKey { Text(text(preferenceNoticeKey)).font(.caption) }
                if canUndoIgnore {
                    Button(text("phase2.undoIgnore")) { Task { @MainActor in await undoIgnore() } }
                        .accessibilityIdentifier("phase2.undoIgnore")
                }
            }.padding(NativeLayout.compact).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.top5")).font(.headline) }
    }

    private func candidatesPage(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(text("phase2.all")).font(.headline)
            Text(text("phase2.threshold")).font(.caption)
            if let preferenceNoticeKey {
                Text(text(preferenceNoticeKey)).font(.caption)
                    .accessibilityIdentifier("phase2.preferenceNotice.candidates")
            }
            if canUndoIgnore {
                Button(text("phase2.undoIgnore")) { Task { @MainActor in await undoIgnore() } }
                    .accessibilityIdentifier("phase2.undoIgnore.candidates")
            }
            if snapshot.candidates.isEmpty { Text(text("phase2.empty")) }
            ForEach(snapshot.candidates) { candidate in
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    AnalysisCandidateView(candidate: candidate, text: text, backend: backend, layout: layout, keyboardPool: keyboardPool,
                                          physicalEvidence: physicalEvidence,
                                          viaReference: viaReference,
                                          conflictEvidence: conflictEvidence,
                                          createMapping: createMapping,
                                           ignore: candidate.isIgnored ? nil : ignoreAction(for: candidate.id),
                                           restore: candidate.isIgnored ? restoreAction(for: candidate.id) : nil)
                    Button(text("phase2.viewDetails")) { open(.candidate(candidate.id), focus: "phase2.candidateOpen.\(candidate.id)") }
                        .focused($focusedControl, equals: "phase2.candidateOpen.\(candidate.id)")
                        .accessibilityFocused($accessibilityFocus, equals: "phase2.candidateOpen.\(candidate.id)")
                        .accessibilityIdentifier("phase2.candidateOpen.\(candidate.id)")
                }
            }
            ignoredSection(snapshot)
        }
        .accessibilityIdentifier("phase2.candidates")
    }

    private func ignoredSection(_ snapshot: AnalysisSnapshot) -> some View {
        let entries = IgnoredRecommendationList.entries(persisted: ignoredKeys, candidates: snapshot.candidates)
        return GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                if entries.isEmpty { Text(text("phase2.ignoredEmpty")) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                        if let chord = entry.chord {
                            Text(AnalysisLabels.chord(chord, text: text))
                        } else {
                            Text(String(format: text("phase2.ignoredUnparsed"), entry.id))
                        }
                        if !entry.hasCurrentObservation {
                            Text(text("phase2.ignoredNoObservation")).font(.caption)
                        }
                        Button(text("phase2.restore")) { Task { @MainActor in await restore(entry.id) } }
                            .accessibilityIdentifier("phase2.restore.\(entry.id)")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.ignoredSection")) }
    }

    @ViewBuilder private var detail: some View {
        if let snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeLayout.group) {
                    Button(text("phase2.back")) { closeDetail() }
                        .focused($focusedControl, equals: "phase2.back")
                        .accessibilityFocused($accessibilityFocus, equals: "phase2.back")
                        .accessibilityIdentifier("phase2.back")
                    switch route {
                    case .overview: EmptyView()
                    case .shortcuts:
                        shortcutColumn(AnalysisStatisticGroup.make(snapshot), limit: nil)
                    case .allCandidates: candidatesPage(snapshot)
                    case .applications:
                        applicationColumn(snapshot, total: snapshot.shortcutStatistics.reduce(0) { $0 + $1.sourceCounts.total.value })
                    case .bareKeys:
                        bareColumn(snapshot)
                    case .shortcut(let id):
                        shortcutDetail(snapshot, id: id)
                    case .candidate(let id):
                        if let candidate = snapshot.candidates.first(where: { $0.id == id }) {
                            AnalysisCandidateView(candidate: candidate, text: text, showsScopePicker: true,
                                                  backend: backend, layout: layout, keyboardPool: keyboardPool,
                                                  physicalEvidence: physicalEvidence,
                                                  viaReference: viaReference,
                                                  conflictEvidence: conflictEvidence,
                                                  createMapping: createMapping,
                                                   ignore: candidate.isIgnored ? nil : ignoreAction(for: candidate.id),
                                                   restore: candidate.isIgnored ? restoreAction(for: candidate.id) : nil)
                        }
                    }
                }
                .padding(NativeLayout.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func shortcutDetail(_ snapshot: AnalysisSnapshot, id: String) -> some View {
        if let group = AnalysisStatisticGroup.make(snapshot).first(where: { $0.id == id }) {
            Text(AnalysisLabels.compactChord(group.representative, text: text)).font(.largeTitle.bold())
                .accessibilityLabel(AnalysisLabels.chord(group.representative, text: text))
                .accessibilityAddTraits(.isHeader)
            Text(String(format: text("overview.usesThisCycle"), group.total))
            Text(text("phase2.applications")).font(.headline)
            let uses = group.usesByApplication
            let apps = snapshot.applications.filter { uses[$0.app] != nil }
                .sorted { uses[$0.app, default: 0] > uses[$1.app, default: 0] }
            ForEach(apps, id: \.app) { app in
                LabeledContent(AnalysisLabels.app(app.app, text: text),
                               value: shareLine(uses[app.app, default: 0], total: group.total))
            }
            Divider()
            Text(text("overview.evidence")).font(.headline)
            Text(AnalysisLabels.key(group.representative.keyCode, text: text))
            ForEach(Array(group.variants.enumerated()), id: \.offset) { _, variant in
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    Text(AnalysisLabels.exactChord(variant.chord, text: text)).font(.headline)
                    Text(String(format: text("phase2.sample"), variant.sourceCounts.total.value, variant.distinctDays))
                    Text(AnalysisLabels.sources(variant.sourceCounts, text: text)).font(.caption)
                    if let candidate = snapshot.candidates.first(where: { $0.chord == variant.chord }) {
                        Text(text("phase2.status.\(candidate.status.rawValue)"))
                        Text(planLine(candidate))
                    }
                }
                .accessibilityIdentifier("phase2.variant")
            }
            Divider()
            Text(text("overview.ranking")).font(.headline)
            Text(text("overview.rankExplanation"))
            Text(String(format: text("phase2.weightedSeparate"), group.weightedFrequency))
            Text(text("phase2.eligibilityExact")).font(.caption)
        }
    }

    private func planLine(_ candidate: RecommendationCandidate) -> String {
        switch candidate.simplificationPlan {
        case .positivePreview: return text("phase2.plan.positive")
        case .noShorterCombination: return text("phase2.plan.noShorter")
        case .functionStateUnknown: return text("phase2.plan.fnUnknown")
        case .statefulExcluded: return text("phase2.plan.excluded")
        }
    }

    private func shareLine(_ count: Int64, total: Int64) -> String {
        let percent = total > 0 ? Double(count) / Double(total) * 100 : 0
        return String(format: text("phase2.appPercent"), count, percent)
    }

    private func ignoreAction(for id: String) -> () -> Void {
        { Task { @MainActor in await ignore(id) } }
    }

    private func restoreAction(for id: String) -> () -> Void {
        { Task { @MainActor in await restore(id) } }
    }

    private func open(_ next: AnalysisRoute, focus: String) {
        history.append((route, focus))
        returnFocus = nil
        route = next
    }

    private func closeDetail() {
        guard let (previous, focus) = history.popLast() else { return }
        returnFocus = focus
        route = previous
    }
}

enum AnalysisSurface {
    case overview, candidates, both
}
