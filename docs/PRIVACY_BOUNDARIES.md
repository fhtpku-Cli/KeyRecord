# Phase 1 local privacy checks (T20)

This milestone has no update endpoint or network client. The future update
exception in the normative architecture does not authorize an endpoint here.
T20 adds evidence about the existing product; it does not change capture,
attribution, storage, consent, or Keychain composition.

## Deterministic code evidence

- `PrivacyBoundaryTests` uses fixed synthetic events, a fixed fake key, and a real
  temporary filesystem root. It exercises normalize -> aggregate -> serialize ->
  authenticate/encrypt -> atomic write. Every regular file and its path is scanned,
  including the manifest. All stored aggregate objects are decrypted and checked
  against approved JSON keys; the actual encrypted manifest is opened and compared
  with the store entries. The approved cycle label is present after decryption but
  absent on disk. Temporary roots are removed by test teardown.
- An attributable foreground canary on bare keys leaves no application metadata.
  The shortcut fixture uses reliably unattributable foreground and persists only
  UNKNOWN buckets. Excluded `com.apple.TextEdit` is **closed with zero objects**,
  not converted into a counted UNKNOWN event. This preserves the T8 distinction.
  This test adds no bundleID field to any production model or payload.
- `PrivacySerializationTests` inventories product Codable/Encodable/Decodable
  declarations with an explicit file-qualified registry, checks record and nested
  DTO fields, and compiles a negative probe proving `ObservedKeyEvent` cannot be
  encoded. Store sources cannot accept that event type or normalization output.
  Manifest, keyring metadata and reset-journal Wire DTOs are registered. There are
  currently no product receipt DTOs; adding a serializable type requires review.
  Encrypted preferences may retain configured exclusion IDs; they are user policy,
  not captured foreground-event metadata. Existing attributed shortcut semantics
  are unchanged; this test does not claim to remove all application attribution.
- `PrivacyEgressTests` independently scans product `Sources` and `App/KeyRecordApp`
  for network/shell APIs and HTTP(S) literals outside comments. It excludes tests
  and probes. T19's Release isolation checks remain unchanged.
- `Scripts/audit-product-network.sh <Mach-O>` checks **built executable bytes**
  with `nm -u -arch all` and `strings -a`, including network APIs, socket imports,
  endpoint literals and shell references. Missing, empty, non-Mach-O and symlink
  inputs cannot produce PASS. The ordinary serialized enum value `system` is not
  the imported libc `_system` symbol. Compiled local/socket fixtures prove both
  acceptance and rejection without executing either binary.

Run Q20 with a fresh owned attempt directory:

```sh
bash Scripts/phase1-qa.sh task 20 happy --attempt "$A"
bash Scripts/phase1-qa.sh task 20 failure --attempt "$A"
```

The disjoint root-SPM lanes currently require 8 and 6 XCTest methods respectively.
Failure fixtures cover leaked event fields, bare-key application metadata,
unregistered receipt types, network/shell source, and a linked socket reference.

## Host evidence remains BLOCKED

```sh
bash Scripts/phase1-qa.sh host network --manifest "$A/host.json" --attempt "$A"
```

`hostCases.network` is manifest-required with fixed argv and only the runner's
`{manifest}` / `{attempt}` tokens. `phase1-network-qa.sh` currently exits 2 before
reading a manifest or invoking a controller. Packet captures, filter installations,
product launches, controller invocations and network operations are all zero.
It remains BLOCKED even if a manifest path is supplied: an authorized controller
must first be integrated. This wrapper is not a fake packet-capture implementation.
Spikes CLI tests reject malformed registries and prevent a child's forged PASS
output from qualifying live evidence.

Static symbol absence complements source inspection; it is **not** an OS-enforced
network sandbox, a measurement of transitive system-framework behavior, or an
observed zero-packet result. An authorized host controller must attribute packets
to the product PID over consent/start/pause/restart. Absolute host-wide silence is
not required. No capture, network call, or real event injection is performed here.

## Attempt-local G1 evaluation

Generate and verify a new projection under `$A`, never overwrite the historical
`evidence/phase1/readiness.json` snapshot:

```sh
swift run --package-path Spikes EvidenceValidator current-readiness \
  --historical evidence/phase0 --lifecycle none --output "$A/current-projection.json"
swift run --package-path Spikes EvidenceValidator verify-current-readiness \
  "$A/current-projection.json"
```

Both commands legitimately exit 2 while G1 is BLOCKED. `capture`, `privacy`, and
`encryptedPersistence` live receipts remain missing; fake tests and static audits
are not endorsed producers. `privacy` still requires both
`t20.network.zeroOutbound` and `t20.persistence.noEventLevelData`. Task 7 authorized
host lifecycle evidence, producer endorsement, and architecture §12.4 ARM + Intel
product performance remain independent requirements. FR-P6 full backup is neither
implemented nor passed by these tests. T24 owns publication of updated readiness.

File counts, lengths and filesystem modification times remain known side channels;
system crash dumps and unlocked privileged local access are outside this proof.
