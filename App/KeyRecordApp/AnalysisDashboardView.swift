import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

private enum AnalysisRoute: Hashable {
    case overview
    case shortcuts
    case applications
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
    @State private var returnFocus: String?
    @FocusState private var focusedControl: String?

    var body: some View {
        Group {
            if snapshot == nil && fallbackAggregate == nil {
                locked
            } else {
                ZStack(alignment: .topLeading) {
                    overview.opacity(route == .overview ? 1 : 0)
                        .accessibilityHidden(route != .overview)
                        .allowsHitTesting(route == .overview)
                    if route != .overview { detail }
                }
            }
        }
        .onExitCommand { if route != .overview { closeDetail() } }
        .onChange(of: route) { _, new in
            if new == .overview, let returnFocus { focusedControl = returnFocus }
            else if new != .overview { focusedControl = "phase2.back" }
        }
    }

    private var locked: some View {
        Label(text("aggregate.locked"), systemImage: "lock.circle")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("phase2.locked")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NativeLayout.group) {
                if surface != .candidates {
                    Text(text("phase2.title")).font(.title2)
                    if let statusKey { Text(text(statusKey)) }
                    Text(text("phase2.logicalOnly")).fixedSize(horizontal: false, vertical: true)
                    if let snapshot {
                        totals(shortcutTotal: snapshot.shortcutStatistics.reduce(0) { $0 + $1.sourceCounts.total.value },
                               bareTotal: snapshot.bareKeys.reduce(0) { $0 + $1.sourceCounts.total.value },
                               activeDays: snapshot.activeDayCount)
                        if showsLayoutControls || (snapshot.shouldAskLayout && !layout.hasAsked) {
                            AnalysisLayoutControls(layout: layout, ask: snapshot.shouldAskLayout && !layout.hasAsked,
                                                   text: text, noticeKey: preferenceNoticeKey, saveLayout: saveLayout)
                        }
                        if snapshot.shortcutStatistics.isEmpty && snapshot.bareKeys.isEmpty {
                            Text(text("phase2.emptyCycle")).fixedSize(horizontal: false, vertical: true)
                        }
                        statistics(snapshot)
                        recommendations(snapshot)
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
            .padding(NativeLayout.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("phase2.dashboard")
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

    private func statistics(_ snapshot: AnalysisSnapshot) -> some View {
        let groups = AnalysisStatisticGroup.make(snapshot)
        let shortcutTotal = groups.reduce(Int64(0)) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: NativeLayout.group) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: NativeLayout.group) {
                    shortcutColumn(groups, limit: AnalysisOverviewLimits.shortcuts)
                    applicationColumn(snapshot, total: shortcutTotal, limit: AnalysisOverviewLimits.applications)
                }.frame(minWidth: 720)
                VStack(alignment: .leading, spacing: NativeLayout.group) {
                    shortcutColumn(groups, limit: AnalysisOverviewLimits.shortcuts)
                    applicationColumn(snapshot, total: shortcutTotal, limit: AnalysisOverviewLimits.applications)
                }
            }
            bareColumn(snapshot, limit: AnalysisOverviewLimits.bareKeys)
        }
    }

    private func shortcutColumn(_ groups: [AnalysisStatisticGroup], limit: Int?) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                if groups.isEmpty { Text(text("phase2.shortcutsEmpty")) }
                ForEach(Array((limit.map { Array(groups.prefix($0)) } ?? groups).enumerated()), id: \.element.id) { _, group in
                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                        Text(AnalysisLabels.chord(group.representative, text: text)).font(.headline)
                        Text(String(format: text("phase2.rawUses"), group.total))
                        Text(String(format: text("phase2.weightedSeparate"), group.weightedFrequency)).font(.caption)
                        if ChordRuleTable.v1.classify(group.representative).kind == .stateful {
                            Text(text("phase2.status.statefulExcluded")).font(.caption)
                        }
                        if ChordRuleTable.v1.classify(group.representative).scope == .system {
                            Text(text("classification.system")).font(.caption)
                        }
                        Button(text("phase2.viewDetails")) { open(.shortcut(group.id), focus: "phase2.detail.\(group.id)") }
                            .focused($focusedControl, equals: "phase2.detail.\(group.id)")
                            .accessibilityIdentifier("phase2.detail.\(group.id)")
                    }.accessibilityIdentifier("phase2.stat.shortcut")
                }
                if let limit, groups.count > limit {
                    Button(text("phase2.viewAll")) { open(.shortcuts, focus: "phase2.open.shortcuts") }
                        .focused($focusedControl, equals: "phase2.open.shortcuts")
                        .accessibilityIdentifier("phase2.open.shortcuts")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.shortcuts")) }
    }

    private func applicationColumn(_ snapshot: AnalysisSnapshot, total: Int64, limit: Int?) -> some View {
        let rows = limit.map { Array(snapshot.applications.prefix($0)) } ?? snapshot.applications
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
                if let limit, snapshot.applications.count > limit {
                    Button(text("phase2.viewAll")) { open(.applications, focus: "phase2.open.applications") }
                        .focused($focusedControl, equals: "phase2.open.applications")
                        .accessibilityIdentifier("phase2.open.applications")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.applications")) }
    }

    private func bareColumn(_ snapshot: AnalysisSnapshot, limit: Int?) -> some View {
        let rows = limit.map { Array(snapshot.bareKeys.prefix($0)) } ?? snapshot.bareKeys
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
                if let limit, snapshot.bareKeys.count > limit {
                    Button(text("phase2.viewAll")) { open(.bareKeys, focus: "phase2.open.bare") }
                        .focused($focusedControl, equals: "phase2.open.bare")
                        .accessibilityIdentifier("phase2.open.bare")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.bare")) }
    }

    private func recommendations(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(text("phase2.top5")).font(.headline)
            Text(text("phase2.threshold")).font(.caption)
            if canUndoIgnore {
                Button(text("phase2.undoIgnore")) { Task { @MainActor in await undoIgnore() } }
                    .accessibilityIdentifier("phase2.undoIgnore")
            }
            if let preferenceNoticeKey { Text(text(preferenceNoticeKey)).font(.caption) }
            if snapshot.topRecommendations.isEmpty {
                Text(text(snapshot.candidates.contains { $0.status == .eligible } ? "phase2.noPositive" : "phase2.noEligible"))
            }
            ForEach(snapshot.topRecommendations) { candidate in
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    AnalysisCandidateView(candidate: candidate, text: text, backend: backend, layout: layout, keyboardPool: keyboardPool,
                                          physicalEvidence: physicalEvidence,
                                          viaReference: viaReference,
                                          conflictEvidence: conflictEvidence,
                                          createMapping: createMapping,
                                           ignore: { Task { @MainActor in await ignore(candidate.id) } })
                    Button(text("phase2.viewDetails")) { open(.candidate(candidate.id), focus: "phase2.candidateOpen.\(candidate.id)") }
                        .focused($focusedControl, equals: "phase2.candidateOpen.\(candidate.id)")
                        .accessibilityIdentifier("phase2.candidateOpen.\(candidate.id)")
                }
            }
            Button(text("phase2.showAll")) {
                if let openCandidates { openCandidates() } else { surfaceSwitch() }
            }
            .accessibilityIdentifier("phase2.showAll")
        }
    }

    private func candidatesPage(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(text("phase2.all")).font(.headline)
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
                        .accessibilityIdentifier("phase2.back")
                    switch route {
                    case .overview: EmptyView()
                    case .shortcuts:
                        shortcutColumn(AnalysisStatisticGroup.make(snapshot), limit: nil)
                    case .applications:
                        applicationColumn(snapshot, total: snapshot.shortcutStatistics.reduce(0) { $0 + $1.sourceCounts.total.value }, limit: nil)
                    case .bareKeys:
                        bareColumn(snapshot, limit: nil)
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
            Text(AnalysisLabels.chord(group.representative, text: text)).font(.title3)
            Text(String(format: text("phase2.rawUses"), group.total))
            Text(String(format: text("phase2.weightedSeparate"), group.weightedFrequency))
            Text(text("phase2.eligibilityExact")).font(.caption).fixedSize(horizontal: false, vertical: true)
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
        returnFocus = focus
        route = next
    }

    private func closeDetail() {
        route = .overview
    }

    private func surfaceSwitch() {
        route = .overview
    }
}

enum AnalysisSurface {
    case overview, candidates, both
}
