import XCTest
import KeyRecordCore
import KeyRecordCapture

private struct UnknownSecureInput: SecureInputProvider {
    func secureInputState() async -> SecureInputState { .unknown }
}

final class CaptureProviderTests: XCTestCase {
    func testInjectedSecureInputPreservesUnknown() async {
        // Given: a provider without an authoritative signal.
        let provider: any SecureInputProvider = UnknownSecureInput()
        // When: query it; Then: no fallback to disabled.
        let state = await provider.secureInputState()
        XCTAssertEqual(state, .unknown)
    }
}
