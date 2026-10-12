import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

struct AnalysisCandidateView: View {
    let candidate: RecommendationCandidate
    let text: NativeText
    var showsScopePicker = false
    var ignore: (() -> Void)?
    var restore: (() -> Void)?
    @State private var scopeOverride: Bool?

    private var applicationScope: Binding<Bool> {
        Binding(get: {
            guard candidate.topApplication != nil else { return false }
            if let scopeOverride { return scopeOverride }
            if case .application = candidate.defaultScope { return true }
            return false
        }, set: { scopeOverride = $0 && candidate.topApplication != nil })
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(AnalysisLabels.chord(candidate.chord, text: text)).font(.headline)
                Text(text("phase2.status.\(candidate.status.rawValue)"))
                Text(String(format: text("phase2.sample"), candidate.rawCount, candidate.distinctDays))
                Text(planText)
                Text(readinessText)
                if candidate.simplificationPlan == .positivePreview {
                    ForEach(Array(candidate.triggers.enumerated()), id: \.offset) { _, trigger in
                        Text(String(format: text("phase2.trigger"), AnalysisLabels.chord(trigger.chord, text: text), trigger.logicalKeysSaved))
                            .accessibilityIdentifier("phase2.candidate.trigger")
                    }
                }
                DisclosureGroup(text("phase2.factors")) {
                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                        Text(String(format: text("phase2.score"), candidate.factors.score, candidate.factors.weightedFrequency))
                        if candidate.simplificationPlan == .positivePreview {
                            Text(String(format: text("phase2.burden"), candidate.factors.sourceLogicalKeyCount, candidate.factors.savedPerUse))
                        }
                        Text(String(format: text("phase2.confidence"), candidate.factors.sourceReliability,
                                    candidate.factors.layoutCompleteness, candidate.factors.confidence))
                        Text(String(format: text("phase2.concentration"), candidate.topApplicationShare * 100))
                        Text(text("phase2.formula"))
                        Text(AnalysisLabels.sources(candidate.sourceCounts, text: text))
                        Text(text("phase2.sourceNote"))
                        Text(text("phase2.factorRules"))
                        Text(text("phase2.whyUnverified"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("phase2.candidate.factors")
                DisclosureGroup(text("phase2.provenance")) {
                    Text(AnalysisLabels.exactChord(candidate.chord, text: text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("phase2.candidate.provenance")
                if candidate.status != .statefulExcluded {
                    scopeSection
                    Text(text("phase2.previewOnly")).font(.caption)
                }
                if candidate.isIgnored { Text(text("phase2.ignored")) }
                HStack(spacing: NativeLayout.compact) {
                    if let ignore, !candidate.isIgnored {
                        Button(text("phase2.ignore"), action: ignore)
                            .accessibilityIdentifier("phase2.ignore")
                            .accessibilityLabel(Text(String(format: text("phase2.ignoreNamed"),
                                                            AnalysisLabels.chord(candidate.chord, text: text))))
                    }
                    if let restore, candidate.isIgnored {
                        Button(text("phase2.restore"), action: restore)
                            .accessibilityIdentifier("phase2.restore")
                            .accessibilityLabel(Text(String(format: text("phase2.restoreNamed"),
                                                            AnalysisLabels.chord(candidate.chord, text: text))))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(NativeLayout.compact)
        }
        .accessibilityIdentifier("phase2.candidate")
    }

    private var planText: String {
        switch candidate.simplificationPlan {
        case .positivePreview: return text("phase2.plan.positive")
        case .noShorterCombination: return text("phase2.plan.noShorter")
        case .functionStateUnknown: return text("phase2.plan.fnUnknown")
        case .statefulExcluded: return text("phase2.plan.excluded")
        }
    }

    private var readinessText: String {
        candidate.status == .statefulExcluded ? text("phase2.readiness.excluded") : text("phase2.readiness.unverified")
    }

    @ViewBuilder private var scopeSection: some View {
        if showsScopePicker {
            Picker(text("phase2.scope"), selection: applicationScope) {
                Text(text("phase2.global")).tag(false)
                Text(text("phase2.topApp")).tag(true).disabled(candidate.topApplication == nil)
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("phase2.candidate.scope")
            Text(text("phase2.scopeSession")).font(.caption)
            if let app = candidate.topApplication {
                Text(AnalysisLabels.app(.bundleID(app), text: text))
                Text(text("phase2.browserScope")).font(.caption)
            } else {
                Text(text("phase2.noApp")).font(.caption)
            }
        } else if let app = candidate.topApplication {
            Text(AnalysisLabels.app(.bundleID(app), text: text)).font(.caption)
        }
    }
}
