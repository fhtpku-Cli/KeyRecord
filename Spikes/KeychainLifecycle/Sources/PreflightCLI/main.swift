import Foundation
import LifecyclePreflight

let args = Array(CommandLine.arguments.dropFirst())
if args == ["scenario-no-controller"] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    let data = try encoder.encode(try LifecycleBlockedCause.noController())
    print(String(decoding: data, as: UTF8.self))
    exit(2)
}
guard args.count == 4, args[0] == "--manifest", args[2] == "--attempt" else {
    print("outcome=BLOCKED code=invalidArguments keychainCalls=0 controllerCalls=0")
    exit(2)
}
switch LivePreflight.evaluate(manifestURL: URL(fileURLWithPath: args[1]), attempt: URL(fileURLWithPath: args[3])) {
case .ready:
    // A successful read-only preflight is not lifecycle qualification or authorization to dispatch effects.
    print("outcome=BLOCKED code=lifecycleNotRun preflight=ready keychainCalls=0 controllerCalls=0")
case .blocked(let reason):
    print("outcome=BLOCKED code=\(reason.rawValue) keychainCalls=0 controllerCalls=0")
}
exit(2)
