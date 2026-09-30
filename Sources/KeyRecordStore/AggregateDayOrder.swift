import Foundation
import KeyRecordCore

struct AggregateDayOrder: Codable {
    let schemaVersion: SchemaVersion
    let cycleID: CycleID
    let days: [LocalDay]

    init(_ reducer: AggregationReducer) {
        schemaVersion = .v1
        cycleID = reducer.cycleID
        days = reducer.activeDays
    }

    static func identity(_ cycleID: CycleID) throws -> CanonicalLogicalIdentity {
        try CanonicalLogicalIdentity(objectType: "com.keyrecord.activeDayOrder",
            schemaVersion: 1, logicalIDText: cycleID.rawValue)
    }

    func restoredDays(cycle: CycleID, observed: Set<LocalDay>) throws -> [LocalDay] {
        guard cycleID == cycle, days.count == Set(days).count,
              observed.isSubset(of: Set(days)) else { throw AggregationError.invalidActiveDayOrder }
        // Order is committed before shards; a crash can leave days without durable counts.
        return days.filter { observed.contains($0) }
    }
}
