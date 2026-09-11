import Carbon
import Foundation

guard CommandLine.arguments.contains("--once") else {
    FileHandle.standardError.write(Data("usage: keyrecord-secure-input-status --once\n".utf8))
    exit(64)
}

if IsSecureEventInputEnabled() {
    print("enabled")
} else {
    print("disabled")
}
