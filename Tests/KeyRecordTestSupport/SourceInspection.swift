import Foundation

public enum SourceInspection {
    public static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    public static func swiftFiles(in directory: URL) throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        return try entries.sorted { $0.path < $1.path }.flatMap { entry -> [URL] in
            if try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                return try swiftFiles(in: entry)
            }
            return entry.pathExtension == "swift" ? [entry] : []
        }
    }

    public static func imports(in source: String) throws -> Set<String> {
        let pattern = #"\bimport\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z_0-9]*)"#
        let expression = try NSRegularExpression(pattern: pattern)
        let text = codeOnly(source)
        return Set(expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// Lexically erase comments and strings, retaining line boundaries for source-level contracts.
    public static func codeOnly(_ source: String) -> String {
        let chars = Array(source)
        var output = ""
        var index = 0
        var depth = 0
        var quoted = false
        while index < chars.count {
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if depth > 0 {
                if chars[index] == "/", next == "*" { depth += 1; index += 2 }
                else if chars[index] == "*", next == "/" { depth -= 1; index += 2 }
                else { output += chars[index] == "\n" ? "\n" : " "; index += 1 }
            } else if quoted {
                if chars[index] == "\\" { index += min(2, chars.count - index) }
                else if chars[index] == "\"" { quoted = false; index += 1 }
                else { output += chars[index] == "\n" ? "\n" : " "; index += 1 }
            } else if chars[index] == "/", next == "*" { depth = 1; index += 2; output += " " }
            else if chars[index] == "/", next == "/" {
                while index < chars.count, chars[index] != "\n" { index += 1 }
            } else if chars[index] == "\"" { quoted = true; index += 1; output += " " }
            else { output.append(chars[index]); index += 1 }
        }
        return output
    }

    /// Isolated per-run scratch space. Works under the default SwiftPM `.build`
    /// layout and under an explicit `--scratch-path <attempt>/build/root`;
    /// see `TestArtifactLocator` for the layout-independent resolution.
    public static func scratchDirectory() throws -> URL {
        try TestArtifactLocator.scratchDirectory()
    }

    public static func properties(of type: String, in source: String) throws -> Set<String> {
        let code = codeOnly(source)
        let tokenizer = try NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z_0-9]*|[{}:]"#)
        let tokens = tokenizer.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap {
            Range($0.range, in: code).map { String(code[$0]) }
        }
        var fields: Set<String> = []
        var index = 0
        while index + 1 < tokens.count {
            guard ["struct", "class", "extension"].contains(tokens[index]), tokens[index + 1] == type else {
                index += 1
                continue
            }
            while index < tokens.count, tokens[index] != "{" { index += 1 }
            var depth = 0
            repeat {
                guard index < tokens.count else { break }
                switch tokens[index] {
                case "{": depth += 1
                case "}": depth -= 1
                case "let" where depth == 1, "var" where depth == 1:
                    if index + 1 < tokens.count { fields.insert(tokens[index + 1]) }
                default: break
                }
                index += 1
            } while depth > 0
        }
        return fields
    }

    public struct CommandResult {
        public let status: Int32
        public let output: String
    }

    public static func run(_ arguments: [String], in directory: URL) throws -> CommandResult {
        let outputURL = directory.appendingPathComponent("output-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: try String(contentsOf: outputURL, encoding: .utf8))
    }

    public static func compileCoreProbe(_ source: String, in directory: URL) throws -> CommandResult {
        let probe = directory.appendingPathComponent("Probe.swift")
        try source.write(to: probe, atomically: true, encoding: .utf8)
        let sources = try swiftFiles(in: root.appendingPathComponent("Sources/KeyRecordCore"))
        return try run(["swiftc", "-swift-version", "6", "-typecheck", "-module-name", "CoreBoundaryProbe", "-module-cache-path", directory.appendingPathComponent("module-cache").path] + sources.map(\.path) + [probe.path], in: directory)
    }

    /// Retained for source compatibility. Resolver faults are now reported as
    /// `TestArtifactLocator.LocatorError`, which names the harness as the failing party.
    public enum InspectionError: Error { case missingAttemptBuild }
}
