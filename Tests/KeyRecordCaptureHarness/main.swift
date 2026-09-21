import Foundation

// Live modes stay unavailable until a qualified privacy provider/controller can
// continuously fence capture. The former one-time privacy sample and forced
// unlocked state were insufficient. No host adapter is instantiated here.
do {
    let options = try HarnessOptions.parse(Array(CommandLine.arguments.dropFirst()))
    switch options.mode {
    case .help:
        print(HarnessOptions.usage)
    case .offline:
        let checks = try runOfflineChecks()
        try HarnessReport(outcome: "COMPLETED", code: "offline_fixture_passed",
                          mode: options.mode.rawValue, seconds: nil, checks: checks).emit(to: options.output)
    case .physical, .synthetic:
        try HarnessReport(outcome: "BLOCKED", code: "capture_qualification_unavailable",
                          mode: options.mode.rawValue, seconds: options.seconds, checks: 0).emit(to: options.output)
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("harness: \(error)\n".utf8))
    exit(1)
}
