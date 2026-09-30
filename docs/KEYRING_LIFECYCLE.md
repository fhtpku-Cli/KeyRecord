# Task 11: versioned local keyring

## Current implementation and historical test boundary

As of 2026-10-01, KeyRecordStore's protocol-injected keyring is composed with the
real App-layer `LocalKeychainBackend` on native arm64 macOS 27.0 build 26A428.
`BlockedLiveKeychain` remains closed for unsupported platforms and negative tests.
See [acceptance](PHASE1_ACCEPTANCE.md) and [integrity/deletion](PRODUCT_KEY_INTEGRITY_20261001.md).

The actual policy is non-synchronizable data-protection Keychain
WhenUnlockedThisDeviceOnly, exact owned-account queries and authentication-UI refusal.
Raw reads succeeded during observed screen lock; the independent software lock
boundary remains essential. No AfterFirstUnlock fallback or guaranteed Swift/CryptoKit
copy zeroization is claimed. SecItem calls reside in the App adapter.

Original Q11 fake tests and `KeyringLifecycleHostTests` did not operate real
Keychain items. Their blocked-boundary receipts remain historical results, not the
verdict on later signed product cases. No historical receipt is regenerated.

## Port obligations

- A single `KeychainKeyring` actor serializes calls across suspension with an explicit busy latch.
  `ProtectedReferenceProviding` additionally leases the store's exclusive writer domain so reset,
  rotation and artifact/reference writers cannot race, even from another keyring instance.
- `KeychainBackend` inventories only the exact service. Unknown accounts must fail closed. Master
  accounts are `master-v<UInt32>` (nonzero); metadata has the fixed `metadata` account. Add rejects
  duplicates; metadata publication is atomic compare-and-replace; deletion is exact and idempotent.
  A production backend must actually meet these atomicity obligations, not simulate CAS with races.
- Consent/store proof and expiry come from an injected port and clock. Bootstrap requires consent,
  independently proven empty storage, absent metadata and empty namespace inventory. Missing keys,
  corrupt manifest/store or metadata never prove freshness. There is no automatic replacement path.
- Metadata v1 uses canonical sorted-key JSON, bounded to 64 KiB, with checked schema/version/set and
  rotation invariants. Duplicate/unknown fields and noncanonical representations fail closed.
- Lock state begins unknown. The injected generation fence cancels asynchronous operations and
  checks every completion before the next step/publication. Handles contain no key bytes; protected
  use is a synchronous, bounded callback. Consumers must not retain bytes or launch asynchronous
  work from it. No guarantee of Swift/Data/CryptoKit copy zeroization is made.
- Store migration gets a scoped `KeyringProtectedAccess` capability, not a reentrant writer call.
  Both required keys are freshly validated, and the capability expires when the operation ends.
  Async implementations must use this capability for protected work and check it before publishing;
  ciphertext-only already-issued durable writes may complete but cannot publish readable state.
- Reference snapshots must explicitly cover all five domains: live entries; fixed manifest;
  unfinished reset/rotation journal envelopes; their old/new/recovery objects; unreconciled owned
  temporary/orphan envelopes. Unknown/unreadable or incomplete coverage blocks retirement.
  The provider is responsible for authenticated recovery/reconciliation, not merely listing headers.

ObjectStore, manifest and reset/rotation journals were subsequently implemented in
KeyRecordStore. The task 11 matrix below records original fake-test boundaries.

## Crash/recovery matrix (deterministic fake)

| Boundary | Durable state and recovery |
|---|---|
| Before new-key add | Old metadata/key unchanged; explicit rotation retry may add new version. |
| After add, before current metadata publish | Old key remains required; new item is an owned unselected candidate. Explicit `rotate(to:)` reuses that exact candidate only after old-key validation. |
| Initial bootstrap add, before metadata publish | `open()` reports `unpublishedCandidates`; `bootstrap()` refuses replacement/publication. Candidate is preserved for explicit operator recovery, not silently adopted. |
| After current metadata publish | Both keys are retained and usable by recovery; no rollback to an uncertain prior publication. |
| Migration / fixed manifest+journal reencryption / reconciliation / scan | Error preserves both keys; idempotent `resumeRotation()` repeats ordered store work. |
| Before retirement-pending publish | Old key retained; fresh recovery scan still required. |
| After retirement-pending publish | Resume must perform a new complete reference scan. Referenced or unreadable state prevents deletion. |
| Before / after exact deletion | Missing old key is tolerated only in retirement-pending and only after a complete scan proves unnecessary. Current and all other required keys must exist and be valid. |
| Before / after metadata removal | Resume converges idempotently to only the current version; no replacement key generation. |
| Lock/unknown during any protected callback | Cancel task, reject stale generation, never invoke a stale plaintext callback or advance to retirement. |

Pending-candidate cleanup requires authenticated reconciliation and complete unreferenced proof,
and deletes only the exact candidate item. It does not delete a current/historical key or any other
namespace. Full product deletion was outside task 11; its later real product-flow result is
recorded in [the integrity/deletion round](PRODUCT_KEY_INTEGRITY_20261001.md).

## QA

From the task 11 worktree, with a fresh absolute `$A` inside `.omo/evidence/repository-status-next-step/`:

```sh
bash Scripts/phase1-qa.sh task 11 happy --attempt "$A"
bash Scripts/phase1-qa.sh task 11 failure --attempt "$A"
swift test --package-path . --scratch-path "$A/build/root"
bash Scripts/phase1-qa.sh host sp6a --manifest "$A/host.json" --attempt "$A"
```

Q11 happy runs 32 fake/boundary tests; failure runs 28 negative/recovery tests. FULL root runs the
43 baseline tests plus 33 additions (including the one BLOCKED-boundary assertion), with zero
skips/failures/unexpected failures. Hosted preflight must be BLOCKED (exit 2), never credited as PASS.
Receipts live in `A/task-11/{happy,failure}` and `A/host/sp6a`; evidence is not committed.
