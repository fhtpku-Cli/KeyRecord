import Foundation

public enum SP5BScenarios {
    public static let deniedNames = [
        "unknown", "set-keyboard-value", "set-keycode", "dynamic-keymap-reset", "custom-set",
        "lighting-or-custom-save", "eeprom-reset", "bootloader", "macro-write", "macro-reset",
        "keymap-write", "encoder-write", "vial-encoder-write", "unlock-start", "unlock-poll",
        "lock", "qmk-settings-write", "qmk-settings-reset", "dynamic-entry-operation",
    ]

    public static func sourceFacts(repository: URL) throws -> SP5BSourceFactsArtifact {
        let qmkHeader = try anchor(repository, .vialQMK, "quantum/vial.h", 25, 26, "5c6acb5dd7f41c5a6307fc5bb46116c47b2908e5df5b36c99119cc25fbe584cc")
        let qmkCommands = try anchor(repository, .vialQMK, "quantum/vial.h", 36, 50, "6d4d0352773a6bc3f256f3e354d45d6bcb0fb33379fc21db3eee5ff44b71f3ac")
        let firmware = try anchor(repository, .vialQMK, "quantum/vial.c", 86, 127, "530fed2e5ce857f08d90f1c635c2497ae338f97812d3122445167609052903fd")
        let guiIdentity = try anchor(repository, .vialGUI, "src/main/python/protocol/keyboard_comm.py", 124, 144, "18097456d26f5ce10d0abb2efb4bc866ee23347a16f03973c52de87bb89f1917")
        let guiKeymap = try anchor(repository, .vialGUI, "src/main/python/protocol/keyboard_comm.py", 196, 216, "186548caef26d38c1e406c547ccd8281e1a6097252cc60822ea78ad3790a1b5e")
        let viaCommands = try anchor(repository, .qmk, "quantum/via.h", 55, 76, "7d086b1a6e13ccb181dc4c0da57f16715a1a727d0cacdc3b910a72bf6611913d")
        let sourcePath = "Spikes/Sources/Phase0Support/VialQuery.swift"
        let source = try bounded(repository.appendingPathComponent(sourcePath), maximum: 131_072)
        let cases = try VialSourceContract.validate(String(decoding: source, as: UTF8.self))
        return SP5BSourceFactsArtifact(
            whitelist: [
                .init(caseID: "protocolVersion", opcode: "0xFE/0x00", packetLayout: "32 bytes: [FE,00,zero x30]", responseLayout: "bytes 0...3 uint32 little-endian", anchors: [qmkHeader, firmware, guiIdentity]),
                .init(caseID: "uid", opcode: "0xFE/0x00", packetLayout: "32 bytes: [FE,00,zero x30]", responseLayout: "bytes 4...11 UID", anchors: [qmkCommands, firmware, guiIdentity]),
                .init(caseID: "definition", opcode: "0xFE/0x01 size; 0xFE/0x02 page", packetLayout: "32 bytes: prefix, opcode, uint16 page little-endian, zero padding", responseLayout: "size uint32 little-endian; pages contain up to 32 definition bytes", anchors: [qmkHeader, qmkCommands, firmware, guiIdentity]),
                .init(caseID: "keymapRead", opcode: "0x12", packetLayout: "32 bytes: [12,uint16 offset big-endian,uint8 length,zero x28]", responseLayout: "bytes 4...(4+length-1), uint16 keycodes big-endian", anchors: [guiKeymap, viaCommands]),
            ],
            denyAllDefault: true,
            reportDescription: "Outbound HID reports are whitelist-constrained non-changing queries; sending a report is not literally read-only and device-side behavior remains unverified without approved capture.",
            publicCases: cases, reportSourcePath: sourcePath,
            reportSourceSha256: ViaDefinitionDigest.sha256(source),
            noPublicRawBytesInitializer: !source.contains(Data("public init(bytes:".utf8)),
            excludedOperationFamilies: deniedNames
        )
    }

    public static func replay(repository: URL) throws -> SP5BReplayArtifact {
        let fixture = try VialRecordedFixture.load(repository: repository)
        let transport = RecordedVialTransport(exchanges: fixture.exchanges)
        let result = try VialQueryReplay.run(
            transport: transport, expectedUID: fixture.expectedUID,
            keymapByteCount: fixture.expectedKeymap.count, timeoutMilliseconds: 250
        )
        return SP5BReplayArtifact(
            fixtureKind: "synthetic-recorded-response", fixturePath: VialRecordedFixture.fixturePath,
            fixtureSha256: VialRecordedFixture.fixtureSha256, protocolVersion: result.protocolVersion,
            uid: result.uid, definitionByteCount: result.definition.count,
            definitionSha256: result.definitionSha256, keymapHex: hex(result.keymap),
            keymapKeycodes: result.keymapKeycodes, reportHex: transport.reports.map { hex($0.bytes) },
            responseSha256: fixture.exchanges.map { ViaDefinitionDigest.sha256(Data($0.response)) },
            reportCount: result.reportCount, timeoutMilliseconds: 250,
            maximumDefinitionBytes: VialQueryLimits.maximumDefinitionBytes,
            maximumKeymapBytes: VialQueryLimits.maximumKeymapBytes,
            maximumKeymapChunkBytes: VialQueryLimits.maximumKeymapChunkBytes
        )
    }

    public static func denyMutation(repository: URL) throws -> SP5BDenyMutationArtifact {
        let attempts: [(String, UInt8, [UInt8])] = [
            ("unknown", 0xFF, []), ("set-keyboard-value", 0x03, []), ("set-keycode", 0x05, []),
            ("dynamic-keymap-reset", 0x06, []), ("custom-set", 0x07, []),
            ("lighting-or-custom-save", 0x09, []), ("eeprom-reset", 0x0A, []), ("bootloader", 0x0B, []),
            ("macro-write", 0x0F, []), ("macro-reset", 0x10, []), ("keymap-write", 0x13, []),
            ("encoder-write", 0x15, []), ("vial-encoder-write", 0xFE, [0x04]),
            ("unlock-start", 0xFE, [0x06]), ("unlock-poll", 0xFE, [0x07]), ("lock", 0xFE, [0x08]),
            ("qmk-settings-write", 0xFE, [0x0B]), ("qmk-settings-reset", 0xFE, [0x0C]),
            ("dynamic-entry-operation", 0xFE, [0x0D]),
        ]
        let transport = RecordedVialTransport(exchanges: [])
        let results = attempts.map { item -> SP5BDeniedAttempt in
            let rejected: Bool
            do { _ = try VialOpcodeGate.authorize(opcode: item.1, payload: item.2); rejected = false }
            catch { rejected = true }
            return .init(name: item.0, opcode: opcode(item.1, item.2), rejected: rejected, transportCallCount: transport.callCount)
        }
        let source = try bounded(repository.appendingPathComponent("Spikes/Sources/Phase0Support/VialQuery.swift"), maximum: 131_072)
        let publicCases = try VialSourceContract.validate(String(decoding: source, as: UTF8.self))
        return .init(
            attempts: results, sourceContractValidated: true, publicCases: publicCases,
            noRawReportEscapeHatch: !source.contains(Data("public init(bytes:".utf8)), denyAllDefault: true
        )
    }

    public static func validates(_ value: SP5BSourceFactsArtifact) -> Bool {
        value.whitelist.map(\.caseID) == VialSourceContract.expectedCases && value.denyAllDefault
            && value.noPublicRawBytesInitializer && value.publicCases == VialSourceContract.expectedCases
            && value.excludedOperationFamilies == deniedNames
            && value.reportDescription.contains("not literally read-only")
    }
    public static func validates(_ value: SP5BReplayArtifact) -> Bool {
        value.fixtureSha256 == VialRecordedFixture.fixtureSha256 && value.protocolVersion == 6
            && value.uid == "0102030405060708" && value.definitionByteCount == 42
            && value.definitionSha256 == "a30cd98ff62e19bbc530d870edd6a64496e1db3b36822065da9cdde77fe4860d"
            && value.keymapKeycodes == [4, 5, 40, 41] && value.reportCount == 6 && value.reportHex.count == 6
    }
    public static func validates(_ value: SP5BDenyMutationArtifact) -> Bool {
        value.attempts.map(\.name) == deniedNames && value.attempts.allSatisfy { $0.rejected && $0.transportCallCount == 0 }
            && value.sourceContractValidated && value.publicCases == VialSourceContract.expectedCases
            && value.noRawReportEscapeHatch && value.denyAllDefault
    }

    private static func anchor(
        _ repository: URL, _ source: Source, _ path: String, _ first: Int, _ last: Int, _ expectedSnippet: String
    ) throws -> SP5BSourceAnchor {
        let copied = "evidence/phase0/sources/repos/\(source.name)/files/\(path)"
        let bytes = try bounded(repository.appendingPathComponent(copied), maximum: 1_048_576)
        guard ViaDefinitionDigest.sha256(bytes) == source.files[path]?.sha256 else { throw SP5BScenarioError.sourceDrift }
        let lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        guard first > 0, last <= lines.count else { throw SP5BScenarioError.sourceDrift }
        let snippet = Data((lines[(first - 1)...(last - 1)].joined(separator: "\n") + "\n").utf8)
        guard ViaDefinitionDigest.sha256(snippet) == expectedSnippet, let file = source.files[path] else { throw SP5BScenarioError.sourceDrift }
        return .init(
            repository: source.name, revision: source.revision, tree: source.tree, path: path,
            gitBlob: file.blob, fileSha256: file.sha256, lineStart: first, lineEnd: last,
            snippetSha256: expectedSnippet, licensePath: source.licensePath,
            licenseGitBlob: source.licenseBlob, licenseSha256: source.licenseSha256
        )
    }

    private static func bounded(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximum else { throw SP5BScenarioError.invalidFile }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private static func opcode(_ opcode: UInt8, _ payload: [UInt8]) -> String {
        ([opcode] + payload).map { String(format: "0x%02X", $0) }.joined(separator: "/")
    }
}

private struct SourceFile { let blob: String; let sha256: String }
private struct Source {
    let name: String; let revision: String; let tree: String; let files: [String: SourceFile]
    let licensePath: String; let licenseBlob: String; let licenseSha256: String
    static let vialQMK = Source(name: "vial-qmk", revision: "dd43959ae5c08d8a28d38a1acf7b04e86b14a344", tree: "b9a0d7b574d78f3e0622c5cfe1f9ff9901d63f64", files: ["quantum/vial.h": .init(blob: "9c66275d4be60fe81a331b401eb22562d5a90233", sha256: "db5ea5a835ba98883302930d1035a9496e6bcbd73373f60fa793cee104c97284"), "quantum/vial.c": .init(blob: "42eb4c5e2ab87ea17b761ef95c311bc470ca94a7", sha256: "713c5a9ba680a3bd39f25fea00cbff66d9506ef8951be33b36aed50b0cc4b52b")], licensePath: "LICENSE", licenseBlob: "d159169d1050894d3ea3b98e1c965c4058208fe1", licenseSha256: "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643")
    static let vialGUI = Source(name: "vial-gui", revision: "aef8222a2d0429a183b2ed692d5f9efcfd383f08", tree: "22a59cd7c2f7c4ef746378e259f6de0f1faa3633", files: ["src/main/python/protocol/keyboard_comm.py": .init(blob: "12b785f6adf2b23239288d3bfd4f43e4e2ada2a9", sha256: "d71b73a6217c5d12a05ff0cd3c85ea06b8f9df798cfb5f1a783207af4623ecdb")], licensePath: "COPYING", licenseBlob: "d159169d1050894d3ea3b98e1c965c4058208fe1", licenseSha256: "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643")
    static let qmk = Source(name: "qmk", revision: "3c73e928ab40b026adcff7112c8fc36a8d96152a", tree: "12276f044f5c8aa2a96075cb72c5d2c2d89955fe", files: ["quantum/via.h": .init(blob: "ef788ebfd85c4d171dcb539f5932964a5a749e0d", sha256: "fdf2231eb0ba8699019b973ba68b685a9782b2fff87be6827bd899e299b76b1a")], licensePath: "LICENSE", licenseBlob: "d159169d1050894d3ea3b98e1c965c4058208fe1", licenseSha256: "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643")
}

public enum SP5BScenarioError: Error, Equatable { case invalidFile, sourceDrift }
