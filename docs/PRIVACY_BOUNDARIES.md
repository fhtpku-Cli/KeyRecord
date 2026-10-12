# Phase 1 local privacy checks (T20)

This milestone has no update endpoint or network client. The future update
exception in the normative architecture does not authorize an endpoint here.
T20 adds evidence about the existing product; it does not change capture,
attribution, storage, consent, or Keychain composition.

Current scope (2026-10-01): the scoped MVP's source and exact signed Release
capability audits completed; see [candidate evidence](RELEASE_CANDIDATE_20261001.md)
and [acceptance](PHASE1_ACCEPTANCE.md). FR-P1 does not require another host packet
capture. Future changed binaries require their own applicable audit; an old audit
does not qualify a new executable. Intel/full G1 and public distribution remain
separate. The missing-audit statements in earlier reports describe those candidates.

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
  currently no formal product receipt DTOs. The Debug-only replay progress
  summary is registered with fixed mode, state, monotonic window time and
  aggregate count fields, including the encrypted-store readback total; it
  contains no captured events or text. Adding another serializable
  type requires review.
  Encrypted preferences may retain configured exclusion IDs; they are user policy,
  not captured foreground-event metadata. Existing attributed shortcut semantics
  are unchanged; this test does not claim to remove all application attribution.
- `PrivacyEgressTests` independently scans product `Sources` and `App/KeyRecordApp`
  for network/shell APIs and HTTP(S) literals outside comments. It excludes tests
  and probes. Later Release integration promoted the exact-item Keychain backend and version-scoped
  lock provider while retaining diagnostic/test-only exclusion.
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

## Historical host network lane

`hostCases.network` is manifest-required with fixed argv and only the runner's
`{manifest}` / `{attempt}` tokens. `phase1-network-qa.sh` currently exits 2 before
reading a manifest or invoking a controller. Packet captures, filter installations,
product launches, controller invocations and network operations are all zero.
It remains BLOCKED even if a manifest path is supplied. This wrapper is retained
as a historical, non-operating lane and is not part of the revised FR-P1 acceptance.
Spikes CLI tests reject malformed registries and prevent a child's forged PASS
output from qualifying live evidence.

FR-P1 now uses the source scan and audit of the exact Release executable being
qualified. The executable audit must be repeated for that candidate; a Debug
loader alone is insufficient. Both checks need their negative fixtures to pass.
These checks establish absence of identified networking capability in the audited
code and binary; they do not claim an OS-enforced sandbox or a measured zero-packet
result. No host capture is required for this milestone's FR-P1 acceptance.

## Historical attempt-local G1 evaluation

Generate and verify a new projection under `$A`, never overwrite the historical
`evidence/phase1/readiness.json` snapshot:

```sh
swift run --package-path Spikes EvidenceValidator current-readiness \
  --historical evidence/phase0 --lifecycle none --output "$A/current-projection.json"
swift run --package-path Spikes EvidenceValidator verify-current-readiness \
  "$A/current-projection.json"
```

These commands explicitly supply `--lifecycle none`; BLOCKED/2 describes that
receipt input set. Old producer receipts are not fabricated or replaced by prose.
This is not a live recomputation of the later scoped MVP, whose signed source/binary
audit and host results are in [acceptance](PHASE1_ACCEPTANCE.md). Short ARM performance
retains its Debug fixed-replay scope. Intel and FR-P6 full backup remain later work.
No packet capture or historical receipt generation is required for this status update.

File counts, lengths and filesystem modification times remain known side channels;
system crash dumps and unlocked privileged local access are outside this proof.
