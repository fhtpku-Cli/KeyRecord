import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

struct AnalysisDashboardView: View {
    let snapshot: AnalysisSnapshot?
    let layout: LayoutPreference
    let text: NativeText
    let saveLayout: @MainActor (LayoutPreset) async -> Void
    @State private var showAll = false
    @State private var savingLayout = false

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: NativeLayout.group) {
                        Text(text("phase2.title")).font(.title2)
                        Text(text("phase2.logicalOnly")).fixedSize(horizontal: false, vertical: true)
                        layoutPanel(snapshot)
                        recommendations(snapshot)
                        statistics(snapshot)
                    }
                    .padding(NativeLayout.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("phase2.dashboard")
            } else {
                Label(text("aggregate.locked"), systemImage: "lock.circle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("phase2.locked")
            }
        }
    }

    private func layoutPanel(_ snapshot: AnalysisSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                if snapshot.shouldAskLayout && !layout.hasAsked {
                    Text(text("phase2.layoutQuestion")).accessibilityIdentifier("phase2.layout.question")
                }
                Text(String(format: text("phase2.layoutCurrent"), AnalysisLabels.layout(layout.preset, text: text)))
                HStack(spacing: NativeLayout.compact) {
                    ForEach([LayoutPreset.ansi, .iso, .alice, .split, .none], id: \.rawValue) { preset in
                        Button(AnalysisLabels.layout(preset, text: text)) {
                            savingLayout = true
                            Task { @MainActor in
                                await saveLayout(preset)
                                savingLayout = false
                            }
                        }
                        .disabled(savingLayout)
                        .accessibilityIdentifier("phase2.layout.\(preset.rawValue)")
                    }
                }
                Text(text("phase2.layoutNote")).font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.layout")) }
    }

    private func statistics(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NativeLayout.group) {
            GroupBox {
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    if snapshot.shortcutStatistics.isEmpty { Text(text("aggregate.emptyState")) }
                    ForEach(AnalysisStatisticGroup.make(snapshot)) { group in
                        VStack(alignment: .leading, spacing: NativeLayout.compact) {
                            Text(AnalysisLabels.chord(group.representative, text: text)).font(.headline)
                            Text(String(format: text("phase2.sources"), group.total, group.ordinary, group.suspected))
                            Text(String(format: text("phase2.frequency"), group.weightedFrequency))
                            if ChordRuleTable.v1.classify(group.representative).kind == .stateful {
                                Text(text("phase2.status.statefulExcluded")).font(.caption)
                            }
                            if ChordRuleTable.v1.classify(group.representative).scope == .system {
                                Text(text("classification.system")).font(.caption)
                            }
                            DisclosureGroup(text("phase2.provenance")) {
                                ForEach(Array(group.variants.enumerated()), id: \.offset) { _, variant in
                                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                                        Text(AnalysisLabels.exactChord(variant.chord, text: text))
                                        Text(AnalysisLabels.sources(variant.sourceCounts, text: text)).font(.caption)
                                    }
                                }
                            }
                        }.accessibilityIdentifier("phase2.stat.shortcut")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text(text("phase2.shortcuts")) }
            GroupBox {
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    if snapshot.applications.isEmpty { Text(text("aggregate.emptyState")) }
                    ForEach(Array(snapshot.applications.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading) {
                            Text(AnalysisLabels.app(row.app, text: text))
                            Text(AnalysisLabels.sources(row.sourceCounts, text: text)).font(.caption)
                        }.accessibilityIdentifier("phase2.stat.application")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text(text("phase2.applications")) }
            GroupBox {
                VStack(alignment: .leading, spacing: NativeLayout.compact) {
                    Text(text("phase2.bareNote")).font(.caption)
                    if snapshot.bareKeys.isEmpty { Text(text("aggregate.emptyState")) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: NativeLayout.page * 8))], alignment: .leading, spacing: NativeLayout.group) {
                        ForEach(Array(snapshot.bareKeys.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                                Text(AnalysisLabels.key(row.keyCode, text: text)).font(.headline)
                                Text(AnalysisLabels.sources(row.sourceCounts, text: text)).font(.caption)
                                ProgressView(value: Double(row.sourceCounts.total.value), total: Double(max(1, snapshot.bareKeys.map { $0.sourceCounts.total.value }.max() ?? 1)))
                                    .accessibilityLabel(AnalysisLabels.key(row.keyCode, text: text))
                                    .accessibilityValue(String(row.sourceCounts.total.value))
                            }.accessibilityIdentifier("phase2.stat.bare")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text(text("phase2.bare")) }
        }
    }

    private func recommendations(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            Text(text(showAll ? "phase2.all" : "phase2.top5")).font(.headline)
            Text(text("phase2.threshold")).font(.caption)
            Toggle(text("phase2.showAll"), isOn: $showAll).accessibilityIdentifier("phase2.showAll")
            if (showAll ? snapshot.candidates : snapshot.topRecommendations).isEmpty {
                Text(text(showAll ? "phase2.empty" : "phase2.noEligible"))
            }
            ForEach(showAll ? snapshot.candidates : snapshot.topRecommendations) { candidate in
                AnalysisCandidateView(candidate: candidate, text: text)
            }
        }
    }
}
