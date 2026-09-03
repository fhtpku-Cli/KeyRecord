import Foundation

@main
public enum Phase0ProbeCommand {
    public static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments == ["help"] || arguments.isEmpty else {
            FileHandle.standardError.write(Data("Phase0Probe task mode is not implemented by scaffold task 1\n".utf8))
            Foundation.exit(64)
        }
        print("Phase0Probe development spike harness; experiment commands begin in later plan tasks.")
    }
}
