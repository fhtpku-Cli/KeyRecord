import Foundation

public enum SP3FixtureScenarios {
    public static let fixtureRelativePath = "evidence/phase0/sources/repos/karabiner/files/tests/src/complex_modifications_assets/json/lint/assets/valid.json"

    public static func managedBlock(repository: URL) throws -> SP3ManagedBlockArtifact {
        let bytes = try Data(contentsOf: repository.appendingPathComponent(fixtureRelativePath))
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let upstreamRules = root["rules"] as? [Any], upstreamRules.count >= 2 else { throw SP3FixtureError.invalidUpstreamFixture }
        let rules = try [upstreamRules[0], upstreamRules[1], upstreamRules[0]].enumerated().map { index, value -> Data in
            guard var object = value as? [String: Any] else { throw SP3FixtureError.invalidUpstreamFixture }
            object["description"] = "KeyRecord copied fixture rule \(index + 1)"
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        let inserted = try KarabinerManagedBlockPlanner.plan(base: bytes, baselineSHA256: AtomicityDigest.sha256(bytes), rules: rules)
        let updated = try KarabinerManagedBlockPlanner.plan(base: inserted.bytes, baselineSHA256: inserted.expectedSHA256, rules: [rules[1]])
        let cleared = try KarabinerManagedBlockPlanner.plan(base: updated.bytes, baselineSHA256: updated.expectedSHA256, rules: [])
        let restored = try KarabinerManagedBlockPlanner.plan(base: cleared.bytes, baselineSHA256: cleared.expectedSHA256, rules: rules)
        let malformed = Data(String(decoding: restored.bytes, as: UTF8.self).replacingOccurrences(of: KarabinerManagedBlock.endDescription, with: "untrusted end").utf8)
        let duplicateRejected = rejects { _ = try KarabinerManagedBlockPlanner.inspect(restored.bytes + restored.bytes) }
        let malformedRejected = rejects { _ = try KarabinerManagedBlockPlanner.inspect(malformed) }
        let baselineRejected = rejects { _ = try KarabinerManagedBlockPlanner.plan(base: bytes, baselineSHA256: String(repeating: "0", count: 64), rules: rules) }
        let external = KarabinerRecovery.classify(currentSHA256: String(repeating: "e", count: 64), hBase: inserted.baselineSHA256, hExpect: inserted.expectedSHA256, rollbackRequested: true)
        return SP3ManagedBlockArtifact(
            upstreamFixturePath: fixtureRelativePath, upstreamFixtureSha256: AtomicityDigest.sha256(bytes),
            insertPreservedOutsideBytes: preserves(inserted), updatePreservedOutsideBytes: preserves(updated),
            clearPreservedOutsideBytes: preserves(cleared), restorePreservedOutsideBytes: preserves(restored),
            threeRuleBatchCount: inserted.ruleCount, malformedRejected: malformedRejected, duplicateRejected: duplicateRejected,
            baselineMismatchRejected: baselineRejected, externalEditRefused: external == .externalChangeRefusal && external.bytesToWrite(beforeImage: bytes) == nil,
            maximumBytes: KarabinerManagedBlockPlanner.maximumBytes, maximumDepth: KarabinerManagedBlockPlanner.maximumDepth
        )
    }

    public static func recovery() -> SP3RecoveryArtifact {
        let hBase = String(repeating: "a", count: 64), hExpect = String(repeating: "b", count: 64), external = String(repeating: "c", count: 64)
        let boundaries = Dictionary(uniqueKeysWithValues: AtomicReplacementCrashBoundary.allCases.map { boundary in
            let current = boundary.isAfterRename ? hExpect : hBase
            return (boundary.rawValue, KarabinerRecovery.classify(currentSHA256: current, hBase: hBase, hExpect: hExpect, rollbackRequested: false).rawValue)
        })
        return SP3RecoveryArtifact(
            hExpect: KarabinerRecovery.classify(currentSHA256: hExpect, hBase: hBase, hExpect: hExpect, rollbackRequested: false).rawValue,
            hBase: KarabinerRecovery.classify(currentSHA256: hBase, hBase: hBase, hExpect: hExpect, rollbackRequested: false).rawValue,
            external: KarabinerRecovery.classify(currentSHA256: external, hBase: hBase, hExpect: hExpect, rollbackRequested: false).rawValue,
            crashBoundaries: boundaries, automaticExternalWrite: false
        )
    }

    public static var formatFacts: SP3FormatFacts {
        SP3FormatFacts(
            upstreamRepository: "https://github.com/pqrs-org/Karabiner-Elements.git",
            upstreamCommit: "865f0e0ee6ebb5f6a6857058b0cbfab8297f8469",
            upstreamTree: "10a85f02a5aa381e8e1523bb25df314a29b6cfa0",
            lintSourcePath: "src/bin/cli/src/main.cpp",
            fixtureSourcePath: "tests/src/complex_modifications_assets/json/lint/assets/",
            currentFormat: "complex modifications asset JSON with title and rules",
            descriptionNotesMinimumVersion: "16.1.23",
            descriptionNotesSourceURL: "https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/description-notes/",
            supportMatrixStatus: .blocked,
            limitation: "Pinned current-format source is inspected; no installed multi-version sample exists, so compatibility and live behavior remain BLOCKED."
        )
    }

    public static func validates(_ artifact: SP3ManagedBlockArtifact) -> Bool {
        artifact.insertPreservedOutsideBytes && artifact.updatePreservedOutsideBytes && artifact.clearPreservedOutsideBytes
            && artifact.restorePreservedOutsideBytes && artifact.threeRuleBatchCount == 3 && artifact.malformedRejected
            && artifact.duplicateRejected && artifact.baselineMismatchRejected && artifact.externalEditRefused
            && artifact.maximumBytes == KarabinerManagedBlockPlanner.maximumBytes && artifact.maximumDepth == KarabinerManagedBlockPlanner.maximumDepth
    }

    private static func preserves(_ plan: KarabinerManagedBlockPlan) -> Bool {
        plan.bytes.prefix(plan.replacementRange.lowerBound) == plan.base.prefix(plan.replacementRange.lowerBound)
            && plan.bytes.suffix(plan.base.count - plan.replacementRange.upperBound) == plan.base.suffix(plan.base.count - plan.replacementRange.upperBound)
    }
    private static func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
}

private enum SP3FixtureError: Error { case invalidUpstreamFixture }
