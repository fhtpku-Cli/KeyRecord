import Foundation
import Phase0Support

// CLI surface for the task 15 closeout artifacts. The readiness projection and
// the task 4 candidate snapshot own their own verbs; this handler only derives
// the status table from a decoded projection and labels the interim envelope.
enum CurrentCloseoutCommand {
    static func execute(_ arguments: [String], repository: URL) throws {
        guard let verb = arguments.first else { throw ValidatorError("usage", "closeout") }
        let base = URL(fileURLWithPath: repository.path, isDirectory: true)
        switch verb {
        case "current-status-table":
            let options = try CloseoutOptions(Array(arguments.dropFirst()))
            let readiness = try options.required("--readiness")
            let output = try options.required("--output")
            try options.rejectUnused()
            let bytes: Data
            do { bytes = try Data(contentsOf: URL(fileURLWithPath: readiness, relativeTo: base)) }
            catch { throw ValidatorError("missing_input", readiness) }
            let table = try CurrentStatusTableGenerator.generate(readinessBytes: bytes)
            try writeExclusive(try Canonical.encode(table), to: URL(fileURLWithPath: output, relativeTo: base), label: output)
            let g0 = CurrentStatusTableGenerator.gateStatus(table.rows, id: .g0) ?? ReadinessStatus.blocked.rawValue
            print("CURRENT_STATUS_TABLE=\(table.overall) g0=\(g0) output=\(output)")
        case "current-interim-envelope":
            let options = try CloseoutOptions(Array(arguments.dropFirst()))
            let candidate = try options.required("--candidate")
            let readiness = try options.required("--readiness")
            let statusTable = try options.required("--status-table")
            let output = try options.required("--output")
            let generatedAt = try options.required("--generated-at")
            try options.rejectUnused()
            let envelope = try CurrentInterimEnvelopeGenerator.generate(
                candidateBytes: try read(URL(fileURLWithPath: candidate, relativeTo: base), label: candidate),
                readinessBytes: try read(URL(fileURLWithPath: readiness, relativeTo: base), label: readiness),
                statusTableBytes: try read(URL(fileURLWithPath: statusTable, relativeTo: base), label: statusTable),
                generatedAt: generatedAt)
            try writeExclusive(try Canonical.encode(envelope), to: URL(fileURLWithPath: output, relativeTo: base), label: output)
            print("CURRENT_INTERIM_ENVELOPE=EMITTED kind=\(CurrentInterimEnvelopeGenerator.kind) output=\(output)")
        default:
            throw ValidatorError("usage", String(verb))
        }
    }

    private static func read(_ url: URL, label: String) throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw ValidatorError("missing_input", label) }
    }

    private static func writeExclusive(_ data: Data, to url: URL, label: String) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
        } catch { throw ValidatorError("closeout_output_unavailable", label) }
    }
}

private final class CloseoutOptions {
    private var values: [String: String] = [:]
    init(_ arguments: [String]) throws {
        guard arguments.count.isMultiple(of: 2) else { throw ValidatorError("usage") }
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), values[key] == nil else { throw ValidatorError("usage", key) }
            values[key] = arguments[index + 1]
            index += 2
        }
    }
    func required(_ key: String) throws -> String {
        guard let value = values.removeValue(forKey: key) else { throw ValidatorError("usage", "missing \(key)") }
        return value
    }
    func rejectUnused() throws { guard values.isEmpty else { throw ValidatorError("usage", values.keys.sorted().joined(separator: ",")) } }
}
