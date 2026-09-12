import Foundation
import Security

/// Entropy only. This adapter never accesses Keychain and is isolated from availability decisions.
public struct SystemMasterMaterial: MasterMaterialGenerating {
    public init() {}
    public func generate() throws -> Data {
        var material = Data(count: 32)
        let status = material.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard status == errSecSuccess else { throw KeyringError.entropyDenied }
        return material
    }
}
