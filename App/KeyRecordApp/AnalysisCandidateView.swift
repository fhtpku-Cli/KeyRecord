import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

struct AnalysisCandidateView: View {
    let candidate: RecommendationCandidate
    let text: NativeText
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
                DisclosureGroup(text("phase2.factors")) {
                    VStack(alignment: .leading, spacing: NativeLayout.compact) {
                        Text(String(format: text("phase2.score"), candidate.factors.score, candidate.factors.weightedFrequency))
                        Text(String(format: text("phase2.burden"), candidate.factors.sourceLogicalKeyCount, candidate.factors.savedPerUse))
                        Text(String(format: text("phase2.confidence"), candidate.factors.sourceReliability,
                                    candidate.factors.layoutCompleteness, candidate.factors.confidence))
                        Text(String(format: text("phase2.concentration"), candidate.topApplicationShare * 100))
                        Text(text("phase2.formula"))
                        Text(AnalysisLabels.sources(candidate.sourceCounts, text: text))
                        Text(text("phase2.sourceNote"))
                        Text(text("phase2.factorRules"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("phase2.candidate.factors")
                DisclosureGroup(text("phase2.provenance")) {
                    Text(AnalysisLabels.exactChord(candidate.chord, text: text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("phase2.candidate.provenance")
                if candidate.status != .statefulExcluded {
                    Picker(text("phase2.scope"), selection: applicationScope) {
                        Text(text("phase2.global")).tag(false)
                        Text(text("phase2.topApp")).tag(true).disabled(candidate.topApplication == nil)
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityIdentifier("phase2.candidate.scope")
                    if let app = candidate.topApplication {
                        Text(AnalysisLabels.app(.bundleID(app), text: text))
                        Text(text("phase2.browserScope")).font(.caption)
                    } else {
                        Text(text("phase2.noApp")).font(.caption)
                    }
                    if candidate.triggers.isEmpty {
                        Text(text("phase2.noTriggers"))
                    } else {
                        ForEach(Array(candidate.triggers.enumerated()), id: \.offset) { _, trigger in
                            Text(String(format: text("phase2.trigger"), AnalysisLabels.chord(trigger.chord, text: text), trigger.logicalKeysSaved))
                                .accessibilityIdentifier("phase2.candidate.trigger")
                        }
                    }
                    Text(text("phase2.previewOnly")).font(.caption)
                }
                if candidate.isIgnored { Text(text("phase2.ignored")) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(NativeLayout.compact)
        }
        .accessibilityIdentifier("phase2.candidate")
    }
}
