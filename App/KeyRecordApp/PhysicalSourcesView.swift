import SwiftUI
import KeyRecordCore
import KeyRecordAnalysis

private struct PhysicalSourcesKey: EnvironmentKey {
    static let defaultValue: PhysicalSourcesModel? = nil
}
extension EnvironmentValues {
    var physicalSources: PhysicalSourcesModel? {
        get { self[PhysicalSourcesKey.self] }
        set { self[PhysicalSourcesKey.self] = newValue }
    }
}

struct PhysicalSourcesComparison: View {
    @ObservedObject var model: PhysicalSourcesModel
    let source: Chord
    let trigger: Chord
    let scope: RecommendationScope
    let text: NativeText
    @State private var expanded = false
    var body: some View {
        let report = model.report(scope)
        VStack(alignment: .leading, spacing: NativeLayout.compact) {
            PhysicalComparisonResult(source: source, trigger: trigger, scope: scope, evidence: report?.evidence, text: text)
            Button { expanded.toggle() } label: {
                Label(text("physical.sources.title"), systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("physical.sources.disclosure")
            if expanded {
                ForEach(report?.sources ?? []) { row in
                    Text(text("physical.sources." + row.id.rawValue) + ": " + text("physical.sources." + row.status.rawValue))
                        .accessibilityIdentifier("physical.source." + row.id.rawValue)
                }
                Text(text("physical.association.title") + ": " + text("physical.association." + (report?.deviceLayout?.status.rawValue ?? "unchecked")))
                    .accessibilityIdentifier("physical.association.status")
                if let match = report?.deviceLayout?.match {
                    Text(String(format: text("physical.association.match"), match.layoutName,
                        String(format: "%04X:%04X", match.vendorProductID >> 16, match.vendorProductID & 0xffff)))
                        .accessibilityIdentifier("physical.association.match")
                }
                Text(text("physical.sources.note")).fixedSize(horizontal: false, vertical: true)
                Button(text("physical.sources.refresh")) { Task { await model.refresh(scope) } }
                    .disabled(model.isLoading(scope))
                    .accessibilityIdentifier("physical.sources.refresh")
            }
        }
    }
}
