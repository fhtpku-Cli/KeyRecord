import Foundation

/// Coarse offline receipt; it does not query permissions, processes or session state.
struct HarnessReport: Encodable {
    let outcome: String
    let code: String
    let mode: String
    let seconds: Int?
    let checks: Int
    let tapCreations = 0
    let postedEvents = 0

    func emit(to url: URL?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        // A failed requested receipt must fail the command, not silently claim success.
        if let url { try data.write(to: url, options: .atomic) }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
