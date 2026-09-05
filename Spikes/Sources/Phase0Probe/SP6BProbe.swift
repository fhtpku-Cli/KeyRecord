import Foundation

enum SP6BProbe {
    static func run(arguments: [String]) throws {
        guard arguments.count == 5, arguments[0] == "sp6b", arguments[1] == "--environment",
              arguments[3] == "--output" else { throw ProbeError.usage }
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = repository.appendingPathComponent("Spikes/Scripts/run-sp6b.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--environment", arguments[2], "--output", arguments[4]]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SP6BProbeError.execution(process.terminationStatus) }
    }
}

enum SP6BProbeError: Error, Equatable { case execution(Int32) }
