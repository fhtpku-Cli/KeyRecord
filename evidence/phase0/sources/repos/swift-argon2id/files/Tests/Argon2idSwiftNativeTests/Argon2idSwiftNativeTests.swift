import CryptoKit
import Foundation
import Testing
@testable import Argon2idSwiftNative

@Suite("Argon2idSwiftNative")
struct Argon2idSwiftNativeTests {
    @Test("BLAKE2b-512 empty message vector is stable")
    func blake2bEmptyMessageVector() throws {
        let digest = PureSwiftArgon2id.blake2b(Data(), outputByteCount: 64)

        #expect(digest == (try Data(hex: """
        786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419
        d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce
        """)))
    }

    @Test("RFC 9106 Argon2id prehash digest matches")
    func rfc9106Argon2idPrehashDigest() throws {
        let digest = PureSwiftArgon2id.initialHash(
            password: Data(repeating: 0x01, count: 32),
            salt: Data(repeating: 0x02, count: 16),
            memoryKiB: 32,
            iterations: 3,
            parallelism: 4,
            outputByteCount: 32,
            secret: Data(repeating: 0x03, count: 8),
            associatedData: Data(repeating: 0x04, count: 12)
        )

        #expect(digest == (try Data(hex: """
        2889de487eb42ae500c0007ed9252f1069eadec40d5765b485de6dc2437a67b8
        546a2f0acc1a0882db8fcf74714b472e94df421a5da1112ffa11434370a1e997
        """)))
    }

    @Test("RFC 9106 Argon2id vector matches")
    func rfc9106Argon2idVector() throws {
        let tag = try Argon2id.deriveBytes(
            password: Data(repeating: 0x01, count: 32),
            salt: Data(repeating: 0x02, count: 16),
            memoryKiB: 32,
            iterations: 3,
            parallelism: 4,
            outputByteCount: 32,
            secret: Data(repeating: 0x03, count: 8),
            associatedData: Data(repeating: 0x04, count: 12)
        )

        #expect(tag == (try Data(hex: """
        0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659
        """)))
    }

    @Test("Argon2id derives CryptoKit SymmetricKey")
    func deriveSymmetricKey() throws {
        let bytes = try Argon2id.deriveBytes(
            password: Data("password".utf8),
            salt: Data("0123456789abcdef".utf8),
            memoryKiB: 32,
            iterations: 2,
            parallelism: 1
        )
        let key = try Argon2id.deriveKey(
            password: Data("password".utf8),
            salt: Data("0123456789abcdef".utf8),
            memoryKiB: 32,
            iterations: 2,
            parallelism: 1
        )

        #expect(key.withUnsafeBytes { Data($0) } == bytes)
    }

    @Test("Invalid Argon2id parameters are rejected")
    func invalidParameters() {
        #expect(throws: Argon2idError.invalidParameters) {
            _ = try Argon2id.deriveBytes(
                password: Data(),
                salt: Data(),
                memoryKiB: 7,
                iterations: 1,
                parallelism: 1
            )
        }

        #expect(throws: Argon2idError.invalidParameters) {
            _ = try Argon2id.deriveBytes(
                password: Data(),
                salt: Data(),
                memoryKiB: 8,
                iterations: 1,
                parallelism: 1,
                outputByteCount: 3
            )
        }
    }
}

private extension Data {
    init(hex: String) throws {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2) else {
            throw Argon2idError.invalidParameters
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else {
                throw Argon2idError.invalidParameters
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
