import Foundation

public struct SP5BProvenanceFile: Codable, Equatable, Sendable {
    public let path: String
    public let copiedPath: String
    public let gitBlob: String
    public let sha256: String
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case path, copiedPath = "copied_path", gitBlob = "git_blob", sha256
    }
    public init(path: String, copiedPath: String, gitBlob: String, sha256: String) {
        self.path = path; self.copiedPath = copiedPath; self.gitBlob = gitBlob; self.sha256 = sha256
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BProvenanceFile")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        copiedPath = try values.decode(String.self, forKey: .copiedPath)
        gitBlob = try values.decode(String.self, forKey: .gitBlob)
        sha256 = try values.decode(String.self, forKey: .sha256)
    }
}

public struct SP5BProvenanceLicense: Codable, Equatable, Sendable {
    public let path: String
    public let copiedPath: String
    public let gitBlob: String
    public let sha256: String
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case path, copiedPath = "copied_path", gitBlob = "git_blob", sha256
    }
    public init(path: String, copiedPath: String, gitBlob: String, sha256: String) {
        self.path = path; self.copiedPath = copiedPath; self.gitBlob = gitBlob; self.sha256 = sha256
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BProvenanceLicense")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        copiedPath = try values.decode(String.self, forKey: .copiedPath)
        gitBlob = try values.decode(String.self, forKey: .gitBlob)
        sha256 = try values.decode(String.self, forKey: .sha256)
    }
}

public struct SP5BRepositoryProvenance: Codable, Equatable, Sendable {
    public let name: String
    public let url: String
    public let retrievedAt: String
    public let upstreamRef: String
    public let tree: String
    public let files: [SP5BProvenanceFile]
    public let license: SP5BProvenanceLicense
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys {
        case name, url, retrievedAt = "retrieved_at", upstreamRef = "upstream_ref", tree, files, license
    }
    public init(
        name: String, url: String, retrievedAt: String, upstreamRef: String, tree: String,
        files: [SP5BProvenanceFile], license: SP5BProvenanceLicense
    ) {
        self.name = name; self.url = url; self.retrievedAt = retrievedAt; self.upstreamRef = upstreamRef
        self.tree = tree; self.files = files; self.license = license
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BRepositoryProvenance")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        url = try values.decode(String.self, forKey: .url)
        retrievedAt = try values.decode(String.self, forKey: .retrievedAt)
        upstreamRef = try values.decode(String.self, forKey: .upstreamRef)
        tree = try values.decode(String.self, forKey: .tree)
        files = try values.decode([SP5BProvenanceFile].self, forKey: .files)
        license = try values.decode(SP5BProvenanceLicense.self, forKey: .license)
    }
}

public struct SP5BSyntheticProvenanceFile: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case path, sha256 }
    public init(path: String, sha256: String) { self.path = path; self.sha256 = sha256 }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BSyntheticProvenanceFile")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        sha256 = try values.decode(String.self, forKey: .sha256)
    }
}

public struct SP5BSyntheticProvenance: Codable, Equatable, Sendable {
    public let evidenceKind: String
    public let generator: String
    public let files: [SP5BSyntheticProvenanceFile]
    enum CodingKeys: String, CodingKey, CaseIterable, StrictCodingKeys { case evidenceKind, generator, files }
    public init(evidenceKind: String, generator: String, files: [SP5BSyntheticProvenanceFile]) {
        self.evidenceKind = evidenceKind; self.generator = generator; self.files = files
    }
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self, typeName: "SP5BSyntheticProvenance")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        evidenceKind = try values.decode(String.self, forKey: .evidenceKind)
        generator = try values.decode(String.self, forKey: .generator)
        files = try values.decode([SP5BSyntheticProvenanceFile].self, forKey: .files)
    }
}

public enum SP5BProvenanceLedger {
    private static let license = SP5BProvenanceLicense(
        path: "LICENSE", copiedPath: "license/LICENSE",
        gitBlob: "d159169d1050894d3ea3b98e1c965c4058208fe1",
        sha256: "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643"
    )
    public static let repositories: [String: SP5BRepositoryProvenance] = [
        "vial-qmk": .init(
            name: "vial-qmk", url: "https://github.com/vial-kb/vial-qmk.git", retrievedAt: "2026-09-03T18:18:31Z",
            upstreamRef: "dd43959ae5c08d8a28d38a1acf7b04e86b14a344", tree: "b9a0d7b574d78f3e0622c5cfe1f9ff9901d63f64",
            files: [
                file("quantum/vial.c", "42eb4c5e2ab87ea17b761ef95c311bc470ca94a7", "713c5a9ba680a3bd39f25fea00cbff66d9506ef8951be33b36aed50b0cc4b52b"),
                file("quantum/vial.h", "9c66275d4be60fe81a331b401eb22562d5a90233", "db5ea5a835ba98883302930d1035a9496e6bcbd73373f60fa793cee104c97284"),
                file("util/vial_generate_definition.py", "0981f096a33cc054044c4ba478c20468d691676f", "ecd4b1ffeae61a1918ef704eff47f67e2f55ec48944a34a357af6a48abd4caae"),
                file("util/ci_vial_verify_uid.py", "5f98be7c2db04b37f4f26776a0688e4ade97f876", "f93bf26a7d332ab8789141f27c10e69b98159d14aba4f3d7a890d32ec90fa225"),
                file("keyboards/vial_example/vial_rp2040/keymaps/vial/vial.json", "7525baeac5beee45d8c9baf774c77469c6a48b85", "09bdbe2ced2496af1ac7f0e7bf20956acc76b861670afe890b62f53bf512f711"),
            ], license: license
        ),
        "vial-gui": .init(
            name: "vial-gui", url: "https://github.com/vial-kb/vial-gui.git", retrievedAt: "2026-09-03T18:18:40Z",
            upstreamRef: "aef8222a2d0429a183b2ed692d5f9efcfd383f08", tree: "22a59cd7c2f7c4ef746378e259f6de0f1faa3633",
            files: [
                file("src/main/python/protocol/keyboard_comm.py", "12b785f6adf2b23239288d3bfd4f43e4e2ada2a9", "d71b73a6217c5d12a05ff0cd3c85ea06b8f9df798cfb5f1a783207af4623ecdb"),
                file("src/main/python/editor/keymap_editor.py", "7e89fcca49c273d378d6854b68e33969f1f99b78", "5266420876959c83bf4f2d7c5db177170a67a368e028f6b0813b3d1e9e6e03e1"),
            ], license: .init(path: "COPYING", copiedPath: "license/COPYING", gitBlob: license.gitBlob, sha256: license.sha256)
        ),
        "qmk": .init(
            name: "qmk", url: "https://github.com/qmk/qmk_firmware.git", retrievedAt: "2026-09-03T18:17:31Z",
            upstreamRef: "3c73e928ab40b026adcff7112c8fc36a8d96152a", tree: "12276f044f5c8aa2a96075cb72c5d2c2d89955fe",
            files: [
                file("quantum/via.h", "ef788ebfd85c4d171dcb539f5932964a5a749e0d", "fdf2231eb0ba8699019b973ba68b685a9782b2fff87be6827bd899e299b76b1a"),
                file("quantum/via.c", "9c10840ec51e7e8158d9bb44a78f38e7540597bb", "002f68bbe024ca3b5bdfbbcc0b677b6fdbb4c8bf632540e3733d61a61cabcd7a"),
                file("lib/python/qmk/cli/via2json.py", "0997e9ca9f8e4b4747262dc19272860dd02c0ce0", "f7e8465a7407d8c54d6a0d500c1d71a9d6659d1bf5b67290be453fa00632bff0"),
            ], license: license
        ),
    ]
    public static let synthetic = SP5BSyntheticProvenance(
        evidenceKind: "synthetic", generator: "Spikes/Scripts/generate-synthetic-fixtures.sh",
        files: [
            .init(path: "via-layout.json", sha256: SyntheticFixtureLedger.via.sha256),
            .init(path: "phase0.vil", sha256: SyntheticFixtureLedger.vial.sha256),
            .init(path: "vial-query-replay.json", sha256: VialRecordedFixture.fixtureSha256),
        ]
    )

    private static func file(_ path: String, _ blob: String, _ sha256: String) -> SP5BProvenanceFile {
        .init(path: path, copiedPath: "files/\(path)", gitBlob: blob, sha256: sha256)
    }
}
