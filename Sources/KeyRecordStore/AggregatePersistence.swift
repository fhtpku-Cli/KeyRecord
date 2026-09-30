import Foundation
import KeyRecordCore

public enum AggregatePersistence {
    public static func objects(_ reducer: AggregationReducer) throws -> [FlushObject] {
        try ProtectedProcessing.observe { try encodeObjects(reducer) }
    }

    private static func encodeObjects(_ reducer: AggregationReducer) throws -> [FlushObject] {
        var objects: [FlushObject] = []
        if !reducer.activeDays.isEmpty {
            objects.append(FlushObject(identity: try AggregateDayOrder.identity(reducer.cycleID),
                payload: try JSONEncoder().encode(AggregateDayOrder(reducer))))
        }
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
        let orderIdentity = try AggregateDayOrder.identity(cycleID)
        let order: AggregateDayOrder?
        if entries.contains(where: { $0.identity == orderIdentity }) {
            let bytes = try await store.readProtected(orderIdentity, gate: gate)
            order = try gate.use(generation) { try JSONDecoder().decode(AggregateDayOrder.self, from: bytes) }
        } else {
            order = nil
        }
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
            let observed = Set(shortcuts.map(\.day) + bareKeys.map(\.day))
            return try AggregationReducer(cycleID: cycleID, shortcuts: shortcuts, bareKeys: bareKeys,
                activeDays: order?.restoredDays(cycle: cycleID, observed: observed))
        }
    }
}
