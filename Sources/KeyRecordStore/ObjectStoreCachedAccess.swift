import Foundation
import KeyRecordCore

extension ObjectStore {
    func cachedManifest() -> EncryptedManifest? {
        #if DEBUG
        return ProtectedReadActivity.process.observe(.storeCache) { manifestBox }
        #else
        return manifestBox
        #endif
    }

    func cachedMaterial(_ version: UInt32) -> Data? {
        #if DEBUG
        return ProtectedReadActivity.process.observe(.storeCache) { materialCache[version] }
        #else
        return materialCache[version]
        #endif
    }
}
