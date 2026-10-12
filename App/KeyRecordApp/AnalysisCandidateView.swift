import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

struct AnalysisCandidateView: View {
    let candidate: RecommendationCandidate
    let text: NativeText
    var showsScopePicker = false
    var backend: BackendConnection = .disconnected(.karabiner)
    var layout = LayoutPreference()
    var keyboardPool: Set<KeyCode> = []
    var physicalEvidence: PhysicalEvidence?
    var viaReference: VIAImportedConfiguration?
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
                if let viaReference {
                    Text(text(viaReference.geometry == nil ? "phase2.via.candidateNoGeometry" : "phase2.via.candidateReference")).font(.caption)
                }
                if candidate.simplificationPlan == .positivePreview {
                    ForEach(Array(candidate.triggers.enumerated()), id: \.offset) { _, trigger in
                        VStack(alignment: .leading, spacing: NativeLayout.compact) {
                            Text(String(format: text("phase2.trigger"), AnalysisLabels.chord(trigger.chord, text: text), trigger.logicalKeysSaved))
                                .accessibilityIdentifier("phase2.candidate.trigger")
                            Text(AnalysisReadinessText.label(CandidateConstraints.assess(checkInput(trigger.chord)), text: text))
                                .font(.caption)
                            AnalysisPhysicalComparisonView(source: candidate.chord, trigger: trigger.chord, scope: selectedScope,
                                evidence: physicalEvidence, text: text)
                            if let viaReference, viaReference.geometry != nil {
                                Text(String(format: text("phase2.via.keyMatches"),
                                    viaReference.positionCount(for: candidate.chord.keyCode),
                                    viaReference.positionCount(for: trigger.chord.keyCode))).font(.caption)
                            }
                        }
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
                    if showsScopePicker {
                        AnalysisManualCandidateEditor(source: candidate.chord, scope: selectedScope,
                            backend: backend, layout: layout, keyboardPool: keyboardPool,
                            physicalEvidence: physicalEvidence, text: text)
                            .id(candidate.id)
                    }
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

    private var selectedScope: RecommendationScope {
        if applicationScope.wrappedValue, let app = candidate.topApplication { return .application(app) }
        return .global
    }

    private func checkInput(_ trigger: Chord) -> CandidateCheckInput {
        CandidateCheckInput(source: candidate.chord, trigger: trigger, scope: selectedScope,
            backend: backend, layout: layout, keyboardPool: keyboardPool, physicalEvidence: physicalEvidence)
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

enum AnalysisReadinessText {
    static func label(_ readiness: CandidateReadiness, text: NativeText) -> String {
        switch readiness {
        case .disconnected: return text("phase2.backendDisconnected")
        case .unchecked: return text("phase2.backendUnchecked")
        case .conflict: return text("phase2.backendConflict")
        case .checked: return text("phase2.backendChecked")
        case .unsupported(let reason):
            switch reason {
            case .backend: return text("phase2.unsupported.backend")
            case .keyCode: return text("phase2.unsupported.keyCode")
            case .applicationScope: return text("phase2.unsupported.applicationScope")
            case .fnModifier: return text("phase2.unsupported.fnModifier")
            case .stateful: return text("phase2.unsupported.stateful")
            case .sameChord: return text("phase2.unsupported.sameChord")
            case .unknownModifiers: return text("phase2.unsupported.unknownModifiers")
            }
        }
    }
}

struct AnalysisManualCandidateEditor: View {
    let source: Chord
    let scope: RecommendationScope
    let backend: BackendConnection
    let layout: LayoutPreference
    let keyboardPool: Set<KeyCode>
    let physicalEvidence: PhysicalEvidence?
    let text: NativeText
    @State private var keyCode = ""
    @State private var command: ModifierSideState = .none
    @State private var option: ModifierSideState = .none
    @State private var control: ModifierSideState = .none
    @State private var shift: ModifierSideState = .none
    @State private var fn = false
    @State private var draft = ManualCandidateDraft()
    @State private var errorKey: String?

    init(source: Chord, scope: RecommendationScope, backend: BackendConnection,
         layout: LayoutPreference, keyboardPool: Set<KeyCode>, physicalEvidence: PhysicalEvidence? = nil, text: NativeText,
         initialDraft: ManualCandidateDraft = ManualCandidateDraft()) {
        self.source = source
        self.scope = scope
        self.backend = backend
        self.layout = layout
        self.keyboardPool = keyboardPool
        self.physicalEvidence = physicalEvidence
        self.text = text
        _draft = State(initialValue: initialDraft)
        switch initialDraft.state {
        case .editing: break
        case .awaitingRiskConfirmation(let chord), .accepted(let chord):
            _keyCode = State(initialValue: String(chord.keyCode.value))
            _command = State(initialValue: chord.modifiers.command)
            _option = State(initialValue: chord.modifiers.option)
            _control = State(initialValue: chord.modifiers.control)
            _shift = State(initialValue: chord.modifiers.shift)
            _fn = State(initialValue: chord.modifiers.fn == .active)
        }
    }

    private var modifiers: ModifierSet {
        ModifierSet(command: command, option: option, control: control, shift: shift, fn: fn ? .active : .none)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                Text(text("phase2.manualSession")).font(.caption)
                TextField(text("phase2.manualKeyCode"), text: $keyCode)
                    .accessibilityIdentifier("phase2.manual.keyCode")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading) {
                    modifierPicker("modifier.command", selection: $command)
                    modifierPicker("modifier.option", selection: $option)
                    modifierPicker("modifier.control", selection: $control)
                    modifierPicker("modifier.shift", selection: $shift)
                }
                Toggle(text("modifier.fn"), isOn: $fn).toggleStyle(.checkbox)
                Button(text("phase2.manualPreview")) { propose() }
                    .accessibilityIdentifier("phase2.manual.preview")
                if let errorKey { Text(text(errorKey)).accessibilityIdentifier("phase2.manual.error") }
                switch draft.state {
                case .editing: EmptyView()
                case .awaitingRiskConfirmation(let chord):
                    comparison(chord)
                    Text(text("phase2.manualRisk")).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("phase2.manual.risk")
                    HStack {
                        Button(text("phase2.manualConfirmRisk")) { draft.confirmRisk() }
                            .accessibilityIdentifier("phase2.manual.confirmRisk")
                        Button(text("phase2.manualCancel")) { draft.invalidate() }
                            .accessibilityIdentifier("phase2.manual.cancel")
                    }
                case .accepted(let chord):
                    comparison(chord)
                    Text(AnalysisReadinessText.label(CandidateConstraints.assess(CandidateCheckInput(source: source,
                        trigger: chord, scope: scope, backend: backend, layout: layout, keyboardPool: keyboardPool,
                        physicalEvidence: physicalEvidence)), text: text))
                        .accessibilityIdentifier("phase2.manual.readiness")
                    AnalysisPhysicalComparisonView(source: source, trigger: chord, scope: scope,
                        evidence: physicalEvidence, text: text)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text(text("phase2.manualTitle")) }
        .onChange(of: keyCode) { _, _ in invalidate() }
        .onChange(of: modifiers) { _, _ in invalidate() }
        .onChange(of: scope) { _, _ in invalidate() }
        .onChange(of: backend) { _, _ in invalidate() }
        .onChange(of: layout) { _, _ in invalidate() }
        .onChange(of: keyboardPool) { _, _ in invalidate() }
        .onChange(of: physicalEvidence) { _, _ in invalidate() }
    }

    private func modifierPicker(_ key: String, selection: Binding<ModifierSideState>) -> some View {
        Picker(text(key), selection: selection) {
            Text(text("phase2.modifierNone")).tag(ModifierSideState.none)
            Text(String(format: text("modifier.side.left"), text(key))).tag(ModifierSideState.left)
            Text(String(format: text("modifier.side.right"), text(key))).tag(ModifierSideState.right)
            Text(String(format: text("modifier.side.both"), text(key))).tag(ModifierSideState.both)
        }
    }

    private func comparison(_ chord: Chord) -> some View {
        Text(String(format: text("phase2.manualComparison"), AnalysisLabels.chord(source, text: text),
            LogicalPreviews.keyCount(source), AnalysisLabels.chord(chord, text: text), LogicalPreviews.keyCount(chord)))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func invalidate() {
        draft.invalidate()
        errorKey = nil
    }

    private func propose() {
        do {
            try draft.propose(keyCode: keyCode, modifiers: modifiers)
            errorKey = nil
        } catch let error as ManualCandidateError {
            switch error {
            case .invalidKeyCode: errorKey = "phase2.manualInvalidKey"
            case .modifierAsTerminal: errorKey = "phase2.manualModifierKey"
            case .unknownModifiers: errorKey = "phase2.manualUnknownModifiers"
            case .stateful: errorKey = "phase2.unsupported.stateful"
            }
        } catch {
            errorKey = "phase2.manualInvalidKey"
        }
    }
}

struct AnalysisPhysicalComparisonView: View {
    let source: Chord
    let trigger: Chord
    let scope: RecommendationScope
    let evidence: PhysicalEvidence?
    let text: NativeText

    var body: some View {
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            switch PhysicalAnalysis.compare(source: source, trigger: trigger, scope: scope, evidence: evidence) {
            case .logical(_, _, let reason):
                Text(text("phase2.physicalFallback") + " " + text(reasonKey(reason)))
            case .physical(let a, let b):
                Text(String(format: text("phase2.physicalCounts"), a.pressCount, b.pressCount))
                Text(String(format: text("phase2.physicalSpan"), a.positionDiameter, b.positionDiameter))
                if b.positionDiameter > a.positionDiameter {
                    Text(text("phase2.physicalWider"))
                        .accessibilityIdentifier("phase2.physical.wider")
                }
                Text(text("phase2.physicalCurrentEstimate"))
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func reasonKey(_ reason: PhysicalFallbackReason) -> String {
        switch reason {
        case .missingEvidence, .missingGeometry: return "phase2.physicalMissing"
        case .deviceUncertain: return "phase2.physicalDevice"
        case .scopeMismatch: return "phase2.physicalScope"
        case .incompleteChain, .missingMapping: return "phase2.physicalChain"
        case .unknownModifiers: return "phase2.physicalUnknownModifiers"
        case .noAction: return "phase2.physicalNoAction"
        case .ambiguousAction: return "phase2.physicalAmbiguous"
        case .missingPosition: return "phase2.physicalPosition"
        case .incomparableGeometry: return "phase2.physicalCoordinates"
        case .invalidGeometry: return "phase2.physicalInvalidGeometry"
        case .incompleteInverseCoverage: return "phase2.physicalCoverage"
        case .invalidTransform, .unsupportedGesture: return "phase2.physicalUnsupported"
        case .unavailableTransform(_, let status):
            switch status {
            case .externallyChanged: return "phase2.physicalChanged"
            case .ambiguous: return "phase2.physicalAmbiguous"
            case .multiDeviceUncertain: return "phase2.physicalDevice"
            case .unsupported: return "phase2.physicalUnsupported"
            case .absent, .verified: return "phase2.physicalChain"
            }
        }
    }
}
