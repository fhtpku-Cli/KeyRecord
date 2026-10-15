import Foundation
import KeyRecordConfigurationRead

public enum FirmwareVersionProvider {
    public static func requiredVIADefinition(deviceProtocol: String?) -> String? {
        guard let deviceProtocol, deviceProtocol.hasPrefix("via-"),
              let version = UInt16(deviceProtocol.dropFirst(4)), (7...13).contains(version),
              deviceProtocol == "via-\(version)" else { return nil }
        return version >= 11 ? "v3" : "v2"
    }
    // Files establish format/protocol facts, never the importer build or device qualification.
    public static func axes(bytes: Data, backend: FirmwareBackend,
                            definitionSchema: String? = nil, importer: String? = nil,
                            viaDeviceProtocol: String? = nil, viaKeycodeDialect: String? = nil) throws -> FirmwareVersionAxes {
        _ = try FirmwareDocument(bytes: bytes, backend: backend)
        let root = try JSONDocumentRanges(bytes).root
        switch backend {
        case .via:
            return FirmwareVersionAxes(definitionSchema: definitionSchema, deviceProtocol: viaDeviceProtocol,
                layoutFormat: "via-layout-json", keycodeDialect: viaKeycodeDialect, importer: importer)
        case .vial:
            func integer(_ field: String) -> UInt32? {
                guard let node = root.members[field] else { return nil }
                return UInt32(String(decoding: bytes[node.range], as: UTF8.self))
            }
            let via = integer("via_protocol"), vial = integer("vial_protocol")
            let protocolAxis = via.flatMap { via in vial.map { "via-\(via)/vial-\($0)" } }
            return FirmwareVersionAxes(definitionSchema: definitionSchema, deviceProtocol: protocolAxis,
                layoutFormat: "vial-save-1", keycodeDialect: vial == 6 ? VialKeycodeDialect.name : nil,
                importer: importer)
        }
    }
}
