import Foundation
import Phase0Support

enum HistoricalEvidenceInventoryValidator {
    private static let mutableConclusionPaths = Set([
        "manifest.sha256", "privacy-audit.json", "run-all.json",
    ])
    private static let generatedConclusionPaths = Set(["conclusions.json"] + ConclusionContract.spikeIDs.map {
        "\($0)-CONCLUSION.md"
    })

    static func validate(root: URL, sourceCommit: String, repository: URL) throws {
        let git = GitRunner(
            repository: repository,
            timeout: 10,
            executable: URL(fileURLWithPath: "/usr/bin/git")
        )
        let historical = try historicalInventory(sourceCommit: sourceCommit, git: git)
        guard generatedConclusionPaths.isDisjoint(with: historical.keys) else {
            throw ValidatorError("source_evidence_not_raw")
        }
        let concluded = FileManager.default.fileExists(atPath: root.appendingPathComponent("conclusions.json").path)
        let local = try localInventory(root: root)
        let expectedPaths = concluded ? Set(historical.keys).union(generatedConclusionPaths) : Set(historical.keys)
        guard Set(local.keys) == expectedPaths else {
            let missing = expectedPaths.subtracting(local.keys).sorted().joined(separator: ",")
            let added = Set(local.keys).subtracting(expectedPaths).sorted().joined(separator: ",")
            throw ValidatorError("source_evidence_inventory_mismatch", "missing=[\(missing)] added=[\(added)]")
        }

        let compared = historical.keys.sorted().filter { path in
            historical[path]?.kind == .file && !(concluded && mutableConclusionPaths.contains(path))
        }
        let committed = try batchBlobs(compared.compactMap { historical[$0]?.objectID }, git: git)
        for (path, historicalEntry) in historical {
            guard local[path] == historicalEntry.kind else {
                throw ValidatorError("source_evidence_type_mismatch", path)
            }
        }
        for (index, path) in compared.enumerated() {
            let current = try Data(contentsOf: root.appendingPathComponent(path))
            guard current == committed[index] else {
                throw ValidatorError("source_evidence_bytes_mismatch", path)
            }
        }
    }

    private static func historicalInventory(
        sourceCommit: String,
        git: GitRunner
    ) throws -> [String: HistoricalEntry] {
        let data = try git.run([
            "ls-tree", "-r", "-t", "-z", "--full-tree", sourceCommit, "--", "evidence/phase0",
        ]).stdout
        var result: [String: HistoricalEntry] = [:]
        for record in data.split(separator: 0) {
            let text = String(decoding: record, as: UTF8.self)
            guard let tab = text.firstIndex(of: "\t") else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            let metadata = text[..<tab].split(separator: " ")
            let path = String(text[text.index(after: tab)...])
            if path == "evidence" || path == "evidence/phase0" { continue }
            guard metadata.count == 3, path.hasPrefix("evidence/phase0/") else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            let relative = String(path.dropFirst("evidence/phase0/".count))
            let kind: EntryKind
            switch metadata[1] {
            case "tree": kind = .directory
            case "blob" where metadata[0] == "100644" || metadata[0] == "100755": kind = .file
            default: throw ValidatorError("source_evidence_type_mismatch", relative)
            }
            let entry = HistoricalEntry(kind: kind, objectID: String(metadata[2]))
            guard result.updateValue(entry, forKey: relative) == nil else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
        }
        return result
    }

    private static func batchBlobs(_ objectIDs: [String], git: GitRunner) throws -> [Data] {
        let input = Data((objectIDs.joined(separator: "\n") + "\n").utf8)
        let output = try git.run(["cat-file", "--batch"], input: input).stdout
        var cursor = output.startIndex
        var blobs: [Data] = []
        blobs.reserveCapacity(objectIDs.count)
        for objectID in objectIDs {
            guard let newline = output[cursor...].firstIndex(of: 10) else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            let header = String(decoding: output[cursor..<newline], as: UTF8.self).split(separator: " ")
            guard header.count == 3, header[0] == objectID, header[1] == "blob",
                  let size = Int(header[2]) else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            let start = output.index(after: newline)
            guard let end = output.index(start, offsetBy: size, limitedBy: output.endIndex),
                  end < output.endIndex, output[end] == 10 else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            blobs.append(Data(output[start..<end]))
            cursor = output.index(after: end)
        }
        guard cursor == output.endIndex else {
            throw ValidatorError("source_evidence_inventory_malformed")
        }
        return blobs
    }

    private static func localInventory(root: URL) throws -> [String: EntryKind] {
        let normalizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) else { throw ValidatorError("source_evidence_inventory_mismatch") }
        var result: [String: EntryKind] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            let prefix = normalizedRoot.path + "/"
            let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard normalizedURL.path.hasPrefix(prefix) else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
            let relative = String(normalizedURL.path.dropFirst(prefix.count))
            guard values.isSymbolicLink != true else {
                throw ValidatorError("source_evidence_type_mismatch", relative)
            }
            let kind: EntryKind
            if values.isDirectory == true { kind = .directory }
            else if values.isRegularFile == true { kind = .file }
            else { throw ValidatorError("source_evidence_type_mismatch", relative) }
            guard result.updateValue(kind, forKey: relative) == nil else {
                throw ValidatorError("source_evidence_inventory_malformed")
            }
        }
        return result
    }
}

private enum EntryKind: Equatable {
    case directory
    case file
}

private struct HistoricalEntry {
    let kind: EntryKind
    let objectID: String
}
