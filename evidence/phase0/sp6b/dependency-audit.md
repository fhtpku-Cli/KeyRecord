# SP-6B Argon2id dependency audit

Scope: full pinned implementations and manifests. PHC `f57e61e19229e23c4445b85494dbf7c07de721cb` / tree `ac3dc753ff75ce5a0f243cba1d94582bafe09409`; pure Swift `14d47de1914ac63b368ddb2cfe0f47ffe25f04cf` / tree `4bb860f4c47b4b327ea207da3fe7a007a05c7b81`.

| # | control | status | severity | PHC source anchor | Swift source anchor | review |
| 1 | pins | PASS | Critical | git commit/tree and `Package.swift` | git commit/tree and `Package.swift` | Exact detached revisions and trees verified; branches rejected. |
| 2 | transitive-graph | PASS | High | `Package.swift:12-44` C target only | `Package.swift:17-24` target plus Apple CryptoKit | No third-party transitive runtime dependency. |
| 3 | licenses | PASS | High | `LICENSE:1-13` CC0/Apache-2.0 | `LICENSE:1-21` MIT | Exact license blobs match the source ledger. |
| 4 | advisories | PASS | High | candidate GitHub and OSV pages | candidate GitHub and OSV pages | D12 complete; NVD keyword hits are individually classified and none affect either exact candidate. |
| 5 | maintenance | PASS | Medium | commit date 2021-06-25 | commit date 2026-05-25 | Exact calendar-month scoring gives PHC 0 and Swift 2; no rounding. |
| 6 | ffi-zeroization | PASS | High | `include/argon2.h` context flags; `src/core.c` wipe/free | `Argon2id.swift` pure Swift, no C FFI | PHC clears internal memory and supports password/secret flags; caller-owned Swift Data and derived-key lifecycle remain integration responsibilities. |
| 7 | compiler-flags | PASS | Medium | C89 O3 warnings-as-errors and no strict aliasing | SwiftPM macOS 14 triples | Both architectures compile from fresh exact trees; no native-only CPU flag. |
| 8 | parameter-bounds | PASS | High | `src/core.c` validate_inputs | `Argon2id.swift:81-92` | Salt/output/time/memory/lanes checked; product integration must retain fixed reviewed parameters. |
| 9 | allocation-errors | PASS | High | allocation callbacks and error codes in `src/core.c` | checked parameter domain and Swift allocation | PHC propagates allocation failures; fixed 512 MiB reviewed Swift/C parameters avoid attacker-controlled allocation. |
| 10 | vectors | PASS | Critical | RFC 9106 section 5.3 through `argon2id_ctx` | upstream RFC 9106 test | Both candidates independently produce `0d640d...e659`. |
| 11 | universal-build | PASS | High | six reference C sources | package source | macOS 14 arm64 and x86_64 builds pass; PHC archive contains both slices. |
| 12 | source-loc | PASS | Low | 3,294 audited C/header LOC | 631 audited Swift LOC | Exact included/excluded paths are fixed by the immutable source contract; both reviewed scopes are below 10,000 LOC. |

Unresolved severity totals: Critical: 0; High: 0; Medium: 0; Low: 2.

Residual Low findings: caller-owned password/salt Data zeroization is not guaranteed by either public high-level API; fixed KDF bounds must remain enforced by the future integration. No production dependency is frozen by this spike.
