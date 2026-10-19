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
        return .init(device: observation.device, mapping: .init(mappings: entries, completeInverseFor: []), observedAt: observation.observedAt)
    }
}
