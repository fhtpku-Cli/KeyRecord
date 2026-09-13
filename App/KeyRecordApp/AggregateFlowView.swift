import SwiftUI
import KeyRecordCore

fileprivate typealias CoreAggregateRow = KeyRecordCore.AggregateRow

// MARK: - Chord description

enum ChordDescriptor {
    static func name(_ bucket: ChordBucket, text: NativeText) -> String {
        let chord = bucket.chord
        var words: [String] = []
        let modifiers = chord.modifiers
        if modifiers.command != .none { words.append(text("modifier.command")) }
        if modifiers.option != .none { words.append(text("modifier.option")) }
        if modifiers.control != .none { words.append(text("modifier.control")) }
        if modifiers.shift != .none { words.append(text("modifier.shift")) }
        if modifiers.fn == .active { words.append(text("modifier.fn")) }
        words.append(String(format: text("aggregate.keyToken"), chord.keyCode.value))
        let app: String
        switch bucket.appBucket {
        case .unknown:
            app = text("aggregate.appUnknown")
        case .bundleID(let identifier):
            app = String(format: text("aggregate.app"), identifier)
        }
        return words.joined(separator: "-") + " · " + app
    }

    static func bareName(_ keyCode: KeyCode, text: NativeText) -> String {
        String(format: text("aggregate.keyToken"), keyCode.value)
    }
}

// MARK: - Aggregate flow screen

struct AggregateFlowView: View {
    let snapshot: AggregateSnapshot?
    let text: NativeText

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: NativeLayout.group) {
                if let snapshot {
                    if snapshot.rows.isEmpty {
                        Text(text("aggregate.emptyState"))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("aggregates.empty")
                    } else {
                        totals(snapshot)
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: NativeLayout.compact) {
                                ForEach(Array(snapshot.rows.enumerated()), id: \.offset) { _, row in
                                    present(row)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("aggregates.list")
                    }
                } else {
                    lockedPlaceholder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NativeLayout.compact)
        } label: {
            Text(text("aggregate.title")).accessibilityIdentifier("aggregates.panel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func totals(_ snapshot: AggregateSnapshot) -> some View {
        HStack(spacing: NativeLayout.group) {
            Text(String(format: text("aggregate.totalShortcuts"), snapshot.shortcutTotal))
                .font(.headline).accessibilityIdentifier("aggregates.shortcutTotal")
            Text(String(format: text("aggregate.totalBare"), snapshot.bareKeyTotal))
                .font(.headline).accessibilityIdentifier("aggregates.bareTotal")
        }
    }

    private var lockedPlaceholder: some View {
        HStack(spacing: NativeLayout.compact) {
            Image(systemName: "lock.circle").accessibilityHidden(true)
            Text(text("aggregate.locked")).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aggregates.locked")
    }

    @ViewBuilder
    private func present(_ row: CoreAggregateRow) -> some View {
        switch row.identity {
        case .shortcut(let bucket):
            AggregateRow(name: ChordDescriptor.name(bucket, text: text), text: text,
                         detail: detail(row), rowIdentifier: "aggregates.row")
        case .bareKey(let keyCode):
            AggregateRow(name: ChordDescriptor.bareName(keyCode, text: text), text: text,
                         detail: bareDetail(row), rowIdentifier: "aggregates.bare")
        }
    }

    private func detail(_ row: CoreAggregateRow) -> String {
        var pieces = [String(format: text("aggregate.observed"), row.total)]
        switch row.classification {
        case .stateful: pieces.append(text("classification.stateful"))
        case .system: pieces.append(text("classification.system"))
        case .discrete: break
        }
        pieces.append(text(confidenceKey(row.sourceConfidence)))
        return pieces.joined(separator: " · ")
    }

    private func bareDetail(_ row: CoreAggregateRow) -> String {
        [String(format: text("aggregate.observed"), row.total),
         text(confidenceKey(row.sourceConfidence)),
         text("aggregate.bareNote")].joined(separator: " · ")
    }

    private func confidenceKey(_ confidence: SourceConfidence) -> String {
        switch confidence {
        case .ordinary: "confidence.ordinary"
        case .suspectedInjection: "confidence.suspectedInjection"
        case .unknown: "confidence.unknown"
        }
    }
}
