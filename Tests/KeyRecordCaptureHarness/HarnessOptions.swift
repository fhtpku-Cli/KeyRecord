import Foundation

enum HarnessMode: String { case help, offline, physical, synthetic }

struct HarnessOptions {
    let mode: HarnessMode
    let seconds: Int?
    let output: URL?

    static let usage = """
    Usage: KeyRecordCaptureHarness --help
           KeyRecordCaptureHarness --mode offline [--out PATH]
           KeyRecordCaptureHarness --mode physical|synthetic [--seconds 30...60] [--out PATH]
    Offline runs in-memory fixtures only, with no event tap or posted events.
    Physical and synthetic live modes return BLOCKED before accessing host state.
    """

    static func parse(_ arguments: [String]) throws -> HarnessOptions {
        if arguments.isEmpty || arguments == ["--help"] {
            return HarnessOptions(mode: .help, seconds: nil, output: nil)
        }
        var values: [String: String] = [:]
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            guard ["--mode", "--seconds", "--out"].contains(argument),
                  values[argument] == nil,
                  let value = iterator.next(), !value.isEmpty, !value.hasPrefix("--") else {
                throw HarnessFailure.invalidArguments
            }
            values[argument] = value
        }
        guard let value = values["--mode"], let mode = HarnessMode(rawValue: value), mode != .help else {
            throw HarnessFailure.invalidArguments
        }
        var seconds: Int?
        if let value = values["--seconds"] {
            guard mode != .offline, let number = Int(value), (30...60).contains(number) else {
                throw HarnessFailure.invalidArguments
            }
            seconds = number
        }
        return HarnessOptions(mode: mode, seconds: seconds,
                              output: values["--out"].map { URL(fileURLWithPath: $0) })
    }
}

enum HarnessFailure: Error {
    case invalidArguments
    case offlineCheckFailed(String)
}
