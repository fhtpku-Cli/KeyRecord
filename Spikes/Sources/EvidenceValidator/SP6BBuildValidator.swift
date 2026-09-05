import Foundation
import Phase0Support

struct SP6BVectorInputs: Decodable, Equatable {
    let passwordByte: String; let passwordLength: Int
    let saltByte: String; let saltLength: Int
    let secretByte: String; let secretLength: Int
    let associatedDataByte: String; let associatedDataLength: Int
    let memoryKiB: Int; let iterations: Int; let parallelism: Int; let outputLength: Int
}

struct SP6BVectorReceipt: Decodable {
    let candidateID: String; let commit: String; let tree: String; let command: [String]
    let inputs: SP6BVectorInputs; let expectedTag: String; let observedTag: String
    let harnessSourceSha256: String; let candidateSourceSha256: String?
    let executableSha256: String; let exitStatus: Int
}

struct SP6BObjectReceipt: Decodable {
    let member: String; let machOArchitecture: String; let sourcePath: String
    let sourceBlob: String; let sourceSha256: String; let objectSha256: String
}

struct SP6BSliceReceipt: Decodable {
    let architecture: String; let sliceSha256: String; let members: [SP6BObjectReceipt]
}

struct SP6BBuildArtifact: Decodable {
    let schemaVersion: Int; let generatedAt: String; let recommendedCandidate: String
    let commit: String; let tree: String; let minimumMacOS: String; let architectures: [String]
    let archiveSha256: String; let compilerIdentity: String; let compilerFlags: [String]
    let slices: [SP6BSliceReceipt]; let swiftCandidate: SwiftCandidate; let vectors: [SP6BVectorReceipt]
    struct SwiftCandidate: Decodable { let commit: String; let tree: String; let arm64MacOS14: Bool; let x86_64MacOS14: Bool }
}

enum SP6BBuildValidator {
    static func validate(
        directory: URL, repository: URL, evidence: SP6BEvidence, contract: SP6BSourceContractDocument
    ) throws -> SP6BBuildArtifact {
        let url = directory.appendingPathComponent("build/build.json")
        guard let build = try? JSONDecoder().decode(SP6BBuildArtifact.self, from: Data(contentsOf: url)),
              let phc = contract.candidates.first(where: { $0.id == "phc" }),
              let swift = contract.candidates.first(where: { $0.id == "swift" }) else { throw ValidatorError("sp6b_build_receipt") }
        let flags = ["-mmacosx-version-min=14.0", "-std=c89", "-O3", "-Wall", "-Wextra", "-Werror", "-fno-strict-aliasing"]
        guard build.schemaVersion == 2, build.recommendedCandidate == "phc", build.commit == phc.commit,
              build.tree == phc.tree, build.minimumMacOS == "14.0", build.architectures == ["arm64", "x86_64"],
              build.compilerFlags == flags, Canonical.sha256(Data(build.compilerIdentity.utf8)) == contract.compilerIdentitySha256,
              build.swiftCandidate.commit == swift.commit, build.swiftCandidate.tree == swift.tree,
              build.swiftCandidate.arm64MacOS14, build.swiftCandidate.x86_64MacOS14 else {
            throw ValidatorError("sp6b_build_receipt")
        }
        let archive = directory.appendingPathComponent("build/argon2-universal.a")
        guard Canonical.sha256(try Data(contentsOf: archive)) == build.archiveSha256,
              build.archiveSha256 == contract.deterministicBuild.archiveSha256 else {
            throw ValidatorError("sp6b_build_archive_hash")
        }
        try validateVectors(build.vectors, directory: directory, repository: repository, evidence: evidence, contract: contract)
        try validateArchive(build, archive: archive, contract: phc, deterministic: contract.deterministicBuild)
        return build
    }

    private static func validateVectors(
        _ receipts: [SP6BVectorReceipt], directory: URL, repository: URL,
        evidence: SP6BEvidence, contract: SP6BSourceContractDocument
    ) throws {
        let expectedTag = "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
        let inputs = SP6BVectorInputs(passwordByte: "01", passwordLength: 32, saltByte: "02", saltLength: 16,
            secretByte: "03", secretLength: 8, associatedDataByte: "04", associatedDataLength: 12,
            memoryKiB: 32, iterations: 3, parallelism: 4, outputLength: 32)
        guard receipts.map(\.candidateID) == ["phc", "swift"], let runner = evidence.legs.first?.runnerCommitSha else {
            throw ValidatorError("sp6b_vector_receipt")
        }
        let git = GitRunner(repository: repository, timeout: 10, executable: URL(fileURLWithPath: "/usr/bin/git"))
        for receipt in receipts {
            guard let candidate = contract.candidates.first(where: { $0.id == receipt.candidateID }),
                  receipt.commit == candidate.commit, receipt.tree == candidate.tree, receipt.inputs == inputs,
                  receipt.expectedTag == expectedTag, receipt.observedTag == expectedTag, receipt.exitStatus == 0,
                  SP6BDirectoryValidator.isSHA256(receipt.executableSha256) else { throw ValidatorError("sp6b_vector_receipt", receipt.candidateID) }
            let harness = receipt.candidateID == "phc" ? "Spikes/Scripts/argon-vector.c" : "Spikes/Scripts/argon-swift-vector.swift"
            let harnessData = try git.run(["cat-file", "blob", "\(runner):\(harness)"]).stdout
            guard receipt.harnessSourceSha256 == Canonical.sha256(harnessData) else { throw ValidatorError("sp6b_vector_harness", receipt.candidateID) }
            if receipt.candidateID == "swift" {
                guard receipt.command == ["xcrun", "swiftc", "Argon2id.swift", "argon-swift-vector.swift"],
                      receipt.candidateSourceSha256 == candidate.includedFiles[0].sha256 else { throw ValidatorError("sp6b_vector_source", "swift") }
            } else if receipt.command != ["clang", "argon-vector.c", "argon2-universal.a"] || receipt.candidateSourceSha256 != nil {
                throw ValidatorError("sp6b_vector_source", "phc")
            }
        }
        let phcText = try String(contentsOf: directory.appendingPathComponent("build/phc-vector.txt"), encoding: .utf8)
        let swiftText = try String(contentsOf: directory.appendingPathComponent("build/swift-vector.txt"), encoding: .utf8)
        guard phcText == "PHC_RFC9106_VECTOR=PASS tag=\(expectedTag)\n", swiftText == "\(expectedTag)\n" else {
            throw ValidatorError("sp6b_vector_observation")
        }
    }

    private static func validateArchive(
        _ build: SP6BBuildArtifact, archive: URL, contract: SP6BCandidateContract,
        deterministic: SP6BDeterministicBuildContract
    ) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sp6b-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard build.slices.map(\.architecture).sorted() == ["arm64", "x86_64"] else { throw ValidatorError("sp6b_build_slice_set") }
        let sourceByPath = Dictionary(uniqueKeysWithValues: contract.includedFiles.map { ($0.path, $0) })
        let expectedMembers = ["argon2.o", "core.o", "blake2b.o", "thread.o", "encoding.o", "ref.o"]
        for slice in build.slices {
            guard let expectedSlice = deterministic.slices.first(where: { $0.architecture == slice.architecture }) else {
                throw ValidatorError("sp6b_build_slice_set")
            }
            let thin = temporary.appendingPathComponent("\(slice.architecture).a")
            try run("/usr/bin/lipo", ["-thin", slice.architecture, archive.path, "-output", thin.path], at: temporary)
            guard Canonical.sha256(try Data(contentsOf: thin)) == slice.sliceSha256,
                  slice.sliceSha256 == expectedSlice.sliceSha256,
                  slice.members.map(\.member) == expectedMembers else { throw ValidatorError("sp6b_build_slice", slice.architecture) }
            let listed = try output("/usr/bin/ar", ["-t", thin.path], at: temporary).split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasSuffix(".o") }
            guard listed == expectedMembers else { throw ValidatorError("sp6b_build_member_set", slice.architecture) }
            let extract = temporary.appendingPathComponent("extract-\(slice.architecture)")
            try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
            try run("/usr/bin/ar", ["-x", thin.path], at: extract)
            for member in slice.members {
                guard member.machOArchitecture == slice.architecture, let source = sourceByPath[member.sourcePath],
                      member.sourceBlob == source.blob, member.sourceSha256 == source.sha256 else {
                    throw ValidatorError("sp6b_build_member_source", member.member)
                }
                let object = extract.appendingPathComponent(member.member)
                guard Canonical.sha256(try Data(contentsOf: object)) == member.objectSha256,
                      member.objectSha256 == expectedSlice.objects[member.member],
                      try output("/usr/bin/lipo", ["-archs", object.path], at: extract).trimmingCharacters(in: .whitespacesAndNewlines) == slice.architecture else {
                    throw ValidatorError("sp6b_build_member_object", member.member)
                }
            }
        }
    }

    private static func output(_ executable: String, _ arguments: [String], at directory: URL) throws -> String {
        let pipe = Pipe(); let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments; process.currentDirectoryURL = directory; process.standardOutput = pipe; process.standardError = Pipe()
        try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw ValidatorError("sp6b_build_tool") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func run(_ executable: String, _ arguments: [String], at directory: URL) throws {
        _ = try output(executable, arguments, at: directory)
    }
}
