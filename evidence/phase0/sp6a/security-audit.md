# SP-6A security audit

Unresolved severity totals: Critical: 0; High: 0; Medium: 0; Low: 0.

| ID | Checklist row | Status | Severity | Impact | Likelihood | Source anchor |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | framing-version | PASS | High | Malformed framing could select unsafe parsing; strict exact lengths fail closed. | Likely for untrusted disk bytes. | `AuthenticatedStorage.swift` |
| 2 | aad-tag | PASS | Critical | Header substitution could redirect key or object; every header byte is AAD and the tag is required. | Likely under local file tampering. | CryptoKit AES.GCM snapshot `reference-05.json` |
| 3 | hmac-locator-inputs | PASS | High | Semantic identifiers could leak; HMAC receives the complete object identifier. | Possible with filesystem access. | `SP6AArtifacts.swift` |
| 4 | hkdf-labels | PASS | High | Key reuse could couple locator and encryption compromise; fixed distinct info labels derive 256-bit keys. | Possible if labels collide. | CryptoKit HKDF snapshot `reference-06.json` |
| 5 | key-versions | PASS | High | Missing historical keys could trigger downgrade; envelope keyVersion requires exact dictionary lookup. | Likely during deletion or corruption. | `AuthenticatedStorage.swift` |
| 6 | nonce-policy | PASS | Critical | AES-GCM nonce reuse can destroy confidentiality; fresh 12-byte random nonces and duplicate detection are tested. | Unlikely with system randomness, detectable in tests. | CryptoKit AES.GCM snapshot `reference-05.json` |
| 7 | accessibility-sync | PASS | High | Sync or broad access could export key material; only two ThisDeviceOnly candidates use synchronizable=false. | Possible from query mistakes. | Security SDK `SecItem.h:179-189,219-246,588-618,1033-1055` |
| 8 | plaintext-lifetime-logging | PASS | High | Persisted or logged plaintext defeats encryption; plaintext exists only in bounded Data lifetime and artifacts contain aggregate proofs. | Possible in error paths. | `SP6AProbe.swift` |
| 9 | errors | PASS | High | Fallback after crypto/Keychain errors exposes data; all errors fail closed and publish no storage fallback. | Likely under missing keys or tamper. | `AuthenticatedStorage.swift` |
| 10 | cleanup | PASS | Medium | Residual test keys expand exposure; exact random service is deleted before, after, and on signals with a residue query. | Possible on interruption. | `SP6AKeychainProbe.swift` |
| 11 | atomicity | PASS | High | Partial envelopes could corrupt state; the historical APFS old-or-new artifact and blobs are revalidated. | Possible on disk failure. | `atomicity-citation.json` |

MED-1 | RESOLVED | Medium | Impact: a lifecycle choice without locked/background evidence would misstate key availability. | Likelihood: high on an unlocked-only host; resolution is an INCONCLUSIVE selection.
