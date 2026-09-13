import Foundation
import KeyRecordCore

public enum AggregatePersistence {
    public static func objects(_ reducer: AggregationReducer) throws -> [FlushObject] {
        var objects: [FlushObject] = []
        for day in reducer.activeDays {
            let shortcuts = reducer.shortcuts.filter { $0.day == day }
            let bareKeys = reducer.bareKeys.filter { $0.day == day }
            if !shortcuts.isEmpty {
                objects.append(FlushObject(identity: try .shard(cycleID: reducer.cycleID.rawValue,
                    dayKey: day.label, aggregateType: "shortcut"), payload: try JSONEncoder().encode(shortcuts)))
            }
            if !bareKeys.isEmpty {
                objects.append(FlushObject(identity: try .shard(cycleID: reducer.cycleID.rawValue,
                    dayKey: day.label, aggregateType: "bareKey"), payload: try JSONEncoder().encode(bareKeys)))
            }
        }
        return objects
    }

    public static func restore(cycleID: CycleID, store: ObjectStore,
                               gate: KeyAvailabilityGate) async throws -> AggregationReducer {
        let generation = try gate.begin()
        let entries = try await store.entries()
        var shortcuts: [DailyShortcutAggregate] = []
        var bareKeys: [DailyBareKeyAggregate] = []
        for entry in entries where entry.identity.objectType == CanonicalLogicalIdentity.shardObjectType {
            let components = try entry.identity.shardComponents()
            guard components.cycleID == cycleID.rawValue else { continue }
            let bytes = try await store.readProtected(entry.identity, gate: gate)
            try gate.use(generation) {
                switch components.aggregateType {
                case "shortcut": shortcuts += try JSONDecoder().decode([DailyShortcutAggregate].self, from: bytes)
                case "bareKey": bareKeys += try JSONDecoder().decode([DailyBareKeyAggregate].self, from: bytes)
                default: throw ObjectStoreError.corruption(.manifestUnreadable)
                }
            }
        }
        return try gate.use(generation) {
            try AggregationReducer(cycleID: cycleID, shortcuts: shortcuts, bareKeys: bareKeys)
        }
    }
}
