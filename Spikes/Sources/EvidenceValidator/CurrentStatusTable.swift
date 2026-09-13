import Foundation
import Phase0Support

// Task 15 status table: a row-per-gate projection derived strictly from a decoded
// CurrentReadiness document. The three current rows are the recomputed projection;
// the O6 and SP-6A-HISTORICAL rows restate the SEALED historical assessment and
// stay separate from the current SP6A local-lifecycle gate. The table is an
// interim artifact: complete/finalFreeze are always false here.
struct CurrentStatusTable: Codable, Equatable, Sendable {
    struct ReadinessDigest: Codable, Equatable, Sendable {
        let status: String
        let sha256: String
    }
    struct Row: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let status: String
        let currentProjection: Bool
        let sealedHistorical: Bool
        let causes: [String]
    }
    let schemaVersion: Int
    let overall: String
    let complete: Bool
    let finalFreeze: Bool
    let readiness: ReadinessDigest
    let rows: [Row]
}

enum CurrentStatusTableGenerator {
    static let historicalO6ID = "O6"
    static let historicalSpikeID = "SP-6A"
    static let historicalRowID = "SP-6A-HISTORICAL"

    static func generate(readinessBytes: Data) throws -> CurrentStatusTable {
        let document = try ReadinessDecoding.decode(CurrentReadiness.self, from: readinessBytes)
        var rows: [CurrentStatusTable.Row] = []
        for gate in document.gates {
            rows.append(.init(id: gate.id.rawValue, title: gate.title, status: gate.status.rawValue,
                              currentProjection: true, sealedHistorical: false, causes: gate.unresolvedCauses))
        }
        rows.append(.init(id: Self.historicalO6ID, title: "Sealed historical O6 disposition",
                          status: historicalO6(document), currentProjection: false, sealedHistorical: true, causes: []))
        rows.append(.init(id: Self.historicalRowID, title: "Sealed historical SP-6A verdict",
                          status: historicalSP6A(document), currentProjection: false, sealedHistorical: true, causes: []))
        return CurrentStatusTable(schemaVersion: 1, overall: document.status.rawValue, complete: false, finalFreeze: false,
                                  readiness: .init(status: document.status.rawValue, sha256: Canonical.sha256(readinessBytes)),
                                  rows: rows)
    }

    static func gateStatus(_ rows: [CurrentStatusTable.Row], id: ReadinessGateID) -> String? {
        rows.first { $0.id == id.rawValue }?.status
    }

    private static func historicalO6(_ document: CurrentReadiness) -> String {
        document.historicalAssessment?.oItems.first { $0.id == historicalO6ID }?.status ?? ReadinessStatus.blocked.rawValue
    }

    private static func historicalSP6A(_ document: CurrentReadiness) -> String {
        document.historicalAssessment?.spikes.first { $0.id == historicalSpikeID }?.verdict.rawValue ?? ReadinessStatus.blocked.rawValue
    }
}
