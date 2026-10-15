import Foundation
import KeyRecordConfigurationRead

extension FirmwareDocument {
    public func unverifiedVialSections() throws -> [String] {
        guard backend == .vial else { return [] }
        let covered: Set<String> = ["version", "uid", "via_protocol", "vial_protocol", "layout", "encoder_layout"]
        return try JSONDocumentRanges(bytes).root.members.keys.filter { !covered.contains($0) }.sorted()
    }
}
