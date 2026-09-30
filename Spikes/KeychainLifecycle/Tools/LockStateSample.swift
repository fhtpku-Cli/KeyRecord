import Foundation
import CoreGraphics
import IOKit

// Diagnostic process-start observations only; this is not a product lock authority.
func boolean(_ value: Any?) -> String {
    guard let value = value as? NSNumber,
          CFGetTypeID(value) == CFBooleanGetTypeID() else { return "unknown" }
    return value.boolValue ? "true" : "false"
}

func session() -> [String: String] {
    guard let dictionary = CGSessionCopyCurrentDictionary() as NSDictionary? else {
        return ["available": "false", "onConsole": "unknown",
                "currentUserMatches": "unknown", "screenLocked": "unknown"]
    }
    let matches: String
    if let user = dictionary[kCGSessionUserIDKey] as? NSNumber,
       CFGetTypeID(user) == CFNumberGetTypeID() {
        matches = user.doubleValue == Double(getuid()) ? "true" : "false"
    } else {
        matches = "unknown"
    }
    return ["available": "true", "onConsole": boolean(dictionary[kCGSessionOnConsoleKey]),
            "currentUserMatches": matches,
            "screenLocked": boolean(dictionary["CGSSessionScreenIsLocked"])]
}

let before = session()
let root = IORegistryGetRootEntry(kIOMainPortDefault)
var console = "unknown"
if root != 0 {
    console = boolean(IORegistryEntryCreateCFProperty(
        root, "IOConsoleLocked" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue())
    IOObjectRelease(root)
}
let after = session()
let data = try JSONSerialization.data(withJSONObject: [
    "before": before, "consoleLocked": console, "after": after
], options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
