import Foundation
import XCTest
@testable import EvidenceValidator

extension Phase1QARunnerCliTests {
    private var networkRepository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testNetworkMissingManifestBlocksWithoutNetworkEffects() throws {
        // Given
        let fixture = try makeFixture()
        try FileManager.default.copyItem(at: networkRepository.appendingPathComponent("Scripts/phase1-network-qa.sh"),
            to: fixture.appendingPathComponent("Scripts/phase1-network-qa.sh"))
        // When
        let result = try run(["host", "network", "--manifest", fixture.path + "/absent.json",
            "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 2, result.output)
        XCTAssertTrue(result.output.contains("code=host_preflight_blocked"), result.output)
        let directory = fixture.appendingPathComponent("attempt/host/network")
        let output = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("stdout")))
        let fields = try XCTUnwrap(output as? [String: Any])
        XCTAssertEqual(fields["outcome"] as? String, "BLOCKED")
        for key in ["packetCaptures", "filterInstallations", "controllerInvocations", "productLaunches", "networkOperations"] {
            XCTAssertEqual(fields[key] as? Int, 0, key)
        }
        XCTAssertEqual(fields["liveReceipt"] as? Bool, false)
        let summary = try String(contentsOf: directory.appendingPathComponent("assertion-summary.json"), encoding: .utf8)
        XCTAssertTrue(summary.contains("BLOCKED"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/absent.json"))
    }

    func testNetworkWithoutManifestArgumentIsRejectedBeforeAttemptCreation() throws {
        // Given / When
        let fixture = try makeFixture()
        let result = try run(["host", "network", "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        assertFailure(result, code: "invalid_arguments")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt"))
    }

    func testNetworkTamperedRegistryIsRejectedBeforeChildSpawn() throws {
        // Given
        for mutation in ["manifest", "token", "unknown", "duplicate"] {
            let fixture = try makeFixture()
            let path = fixture.appendingPathComponent("Scripts/phase1-qa-cases.json")
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            var hosts = try XCTUnwrap(document["hostCases"] as? [[String: Any]])
            let index = try XCTUnwrap(hosts.firstIndex { $0["mode"] as? String == "network" })
            let marker = fixture.path + "/spawned"
            hosts[index]["argv"] = ["/usr/bin/touch", marker, "{manifest}", "{attempt}"]
            switch mutation {
            case "manifest": hosts[index]["manifestRequired"] = false
            case "token": hosts[index]["argv"] = ["/usr/bin/touch", marker, "{manifest}", "{attempt}", "{unapproved}"]
            case "unknown": hosts[index]["endpoint"] = "forbidden"
            default: hosts.append(hosts[index])
            }
            document["hostCases"] = hosts
            try JSONSerialization.data(withJSONObject: document).write(to: path)
            // When
            let result = try run(["host", "network", "--manifest", fixture.path + "/absent.json",
                "--attempt", fixture.path + "/attempt"], fixture: fixture)
            // Then
            assertFailure(result, code: "invalid_registry")
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path + "/attempt"))
        }
    }

    func testNetworkForgedPassOutputCannotQualifyLiveReceipt() throws {
        // Given
        let fixture = try makeFixture()
        let path = fixture.appendingPathComponent("Scripts/phase1-qa-cases.json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        document["hostCases"] = [["mode": "network", "manifestRequired": true,
            "argv": ["/usr/bin/printf", "outcome=PASS %s %s\\n", "{manifest}", "{attempt}"], "timeoutSeconds": 10]]
        try JSONSerialization.data(withJSONObject: document).write(to: path)
        // When
        let result = try run(["host", "network", "--manifest", fixture.path + "/absent.json",
            "--attempt", fixture.path + "/attempt"], fixture: fixture)
        // Then
        XCTAssertEqual(result.status, 2, result.output)
        XCTAssertTrue(result.output.contains("outcome=BLOCKED"), result.output)
    }

    func testT20CurrentG1InputsRemainBlockedWithoutEndorsedHostReceipts() throws {
        // Given / When: recompute current inputs; do not trust the historical readiness snapshot.
        let inputs = try CurrentReadinessBindings(repository: networkRepository).load(
            historical: "evidence/phase0", lifecycle: "none", approvedProducerSHA256s: [])
        let current = try CurrentReadinessDeriver.derive(inputs)
        // Then
        XCTAssertTrue(inputs.receipts.isEmpty)
        let gate = try XCTUnwrap(current.gates.first { $0.id == .implementation })
        XCTAssertEqual(gate.status, .blocked)
        for id in ReadinessReceiptID.implementation {
            XCTAssertTrue(gate.unresolvedCauses.contains("receipt.\(id.rawValue)"), id.rawValue)
        }
        XCTAssertTrue(current.retainedReleaseBlockers.contains { $0.id == "FULL_BACKUP_FINAL_RELEASE" })
    }
}
