# SP-6A conclusion

Verdict: **BLOCKED**

AES-256-GCM envelope framing, authenticated header/AAD, random 12-byte nonces, HKDF-SHA256 domain separation, HMAC-SHA256 opaque locators, encrypted manifest/path canaries, historical atomicity binding, and the source security audit passed. The bound runner recorded successful SecRandomCopyBytes input, recomputable RFC 4122 UUIDv4 transformation, nonsentinel entropy, and no namespace reuse in the defined captured attempt scope. Its exact Keychain namespace pre-cleanup returned missing-entitlement, so candidate add/read/attribute/delete assertions did not execute; a residue query found zero items. This does not prove mathematical unpredictability from output alone.

No Keychain accessibility candidate is selected. D9 is BLOCKED because the SwiftPM runner lacks the application identifier entitlement required by the isolated data-protection Keychain; no candidate item was added. Cross-device restore is BLOCKED because no approved second-device restore environment exists. There is no AlwaysThisDeviceOnly use, plaintext fallback, plaintext file/log artifact, or persisted key material.

- `sp6a.atomicity`: PASS
- `sp6a.envelope`: PASS
- `sp6a.hkdfLocator`: PASS
- `sp6a.keychainAfterFirstUnlock`: BLOCKED
- `sp6a.keychainSelection`: BLOCKED
- `sp6a.keychainWhenUnlocked`: BLOCKED
- `sp6a.pathCanary`: PASS
- `sp6a.securityAudit`: PASS
