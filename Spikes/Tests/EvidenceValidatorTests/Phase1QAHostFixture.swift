import Foundation
import XCTest

extension Phase1QARunnerCliTests {
    struct Summary: Decodable {
        let outcome: String
        let code: String
        let childExitStatus: Int
        let runnerExitStatus: Int
        let executed: Int
        let skipped: Int
    }
    struct Result { let status: Int32; let output: String }

    func dryManifest(_ mutation: String) throws -> Data {
        var values: [String: Any] = ["hostID": "fixture-host", "teamID": "FIXTURETEAM", "entitled": true,
                                   "expiresAt": "2034-01-01T00:00:00Z"]
        switch mutation {
        case "expired": values["expiresAt"] = "2000-01-01T00:00:00Z"
        case "wrong-host": values["hostID"] = "other"
        case "wrong-team": values["teamID"] = "other"
        case "missing-entitlement": values.removeValue(forKey: "entitled")
        default: XCTFail("unknown fixture mutation")
        }
        return try JSONSerialization.data(withJSONObject: values)
    }

    func hostRegistry(at fixture: URL) throws {
        let child = fixture.appendingPathComponent("dry-preflight.rb")
        let script = """
        require 'json'
        require 'time'
        manifest, attempt = ARGV
        keychain = 0
        controller = 0
        document = File.file?(manifest) ? JSON.parse(File.read(manifest)) : {}
        ready = document['hostID'] == 'fixture-host' && document['teamID'] == 'FIXTURETEAM' &&
                document['entitled'] == true && Time.iso8601(document['expiresAt']) > Time.at(2000000000)
        unless ready
          File.write(File.join(attempt, 'counts'), "keychain=#{keychain} controller=#{controller}")
          puts 'outcome=BLOCKED keychainCalls=0 controllerCalls=0'
          exit 2
        end
        keychain += 1
        controller += 1
        File.write(File.join(attempt, 'counts'), "keychain=#{keychain} controller=#{controller}")
        exit 0
        """
        try Data(script.utf8).write(to: child)
        let host: [String: Any] = ["mode": "sp6a", "manifestRequired": true,
                                   "argv": ["/usr/bin/ruby", child.path, "{manifest}", "{attempt}"], "timeoutSeconds": 10]
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "cases": [], "hostCases": [host]])
            .write(to: fixture.appendingPathComponent("Scripts/phase1-qa-cases.json"))
    }
}
