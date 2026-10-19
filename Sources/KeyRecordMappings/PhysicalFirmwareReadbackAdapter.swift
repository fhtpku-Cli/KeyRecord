import Foundation
import KeyRecordAnalysis

public enum PhysicalFirmwareReadbackAdapter {
    public static func reference(_ observation: VialKeymapObservation, record: FirmwareBatchRecord) throws -> PhysicalFirmwareReference {
        guard record.backend == .vial, observation.device == record.device, observation.axes == record.axes else {
            throw FirmwareError.identityMismatch
        }
        let entries = observation.values.sorted {
            ($0.key.layer, $0.key.row, $0.key.column) < ($1.key.layer, $1.key.row, $1.key.column)
        }.compactMap { slot, name -> CanonicalTransform.Mapping? in
            guard let hid = try? VialKeycodeDialect.rawValue(name), VIAReferenceParser.standardKeyCode(hidUsage: hid) != nil else { return nil }
            return .init(input: [.position("layer:\(slot.layer)/\(slot.row),\(slot.column)")], output: [.hidUsage(hid)])
        }
        // A readback has no active-layer or timing proof; it never establishes inverse coverage.
        let layout = try layout(observation)
        return .init(device: observation.device, mapping: .init(mappings: entries, completeInverseFor: []),
            observedAt: observation.observedAt, layout: layout)
    }

    private static func layout(_ observation: VialKeymapObservation) throws -> PhysicalLayoutReference? {
        guard let definition = observation.definition else { return nil }
        guard definition.device == observation.device else { throw FirmwareError.identityMismatch }
        guard let parsed = try? VIAReferenceParser.definition(definition.bytes) else { return nil }
        var positions: [PhysicalPosition] = []
        if let geometry = parsed.geometry, !observation.values.isEmpty {
            let layers = Set(observation.values.keys.map(\.layer))
            for layer in layers.sorted() {
                let slots = observation.values.keys.filter { $0.layer == layer }
                guard Set(slots.map { "\($0.row),\($0.column)" }) == Set(geometry.positions.keys) else {
                    return .init(name: parsed.name, vendorProductID: parsed.vendorProductID, geometry: nil)
                }
                for slot in slots {
                    guard let position = geometry.positions["\(slot.row),\(slot.column)"] else { continue }
                    positions.append(try PhysicalPosition(id: "layer:\(layer)/" + position.id, centerX: position.x, centerY: position.y,
                        coordinateFrame: "vial-definition-reference:" + observation.device))
                }
            }
        }
        return .init(name: parsed.name, vendorProductID: parsed.vendorProductID,
            geometry: positions.isEmpty ? nil : try CanonicalGeometry(positions: positions))
    }
}
