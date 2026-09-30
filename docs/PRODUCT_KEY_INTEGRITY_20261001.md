# Product key integrity and deletion

Status: the bounded real Keychain scenario passes on signed
`1b82d7cd6684ec2d23aade709cbc64d176651494`.

## Observed result

The authorized automatic round completed one XCTest case in 7.330 seconds, with
zero failures, skips or runtime warnings. The controller exited normally in
11.102 seconds; the entire round took 12.154 seconds, with no forced termination,
control errors or remaining host. An independent exact-path process check also
returned no target or foreign probe.

Both missing-key and one-byte corrupt-key reconstruction preserved all encrypted
files, left capture/presentation closed and made zero replacement mutations.
Restoring the original material allowed two counts to be read back. The actual
product deletion flow then removed the store and both exact items, verified before
fallback cleanup. Two owned items were confirmed absent. Input and login-item
effects were simulated; the Keychain, encrypted store and product flow were real.

Artifacts are in `/private/tmp/keyrecord-product-integrity-20261001`:
`round.json`, `main-run.json`, `main-run.log`, `main.xcresult` and the exact ownership
record. This attempt is consumed and must not be rerun. The existing-certificate
signed build took 19.601 seconds, and strict host/plugin signature checks passed.
No signing material was requested. Collecting Release and native UI/accessibility
verification remain separate.

## Scenario and preparation

The shared product composition now has one bounded scenario for FR-P7. A fresh
private store and UUID test namespace save two simulated counts. Only the
successfully created `master-v1` is first removed, then separately replaced by
one invalid byte. Each reconstruction must fail with its store gate initially
available, leave capture and sensitive presentation closed, make zero mutations,
and preserve all encrypted files and the metadata item. The original key stays
in process memory and is restored between branches; it is never logged.

After both branches, the reconstructed product must read back two counts. Its
actual `requestDeleteLocalData` / confirmation flow must remove the entire owned
store and both exact Keychain items before fallback cleanup runs. Cleanup checks
absence only for successfully owned accounts. Ownership-journal retry is separate
from cleanup; failed persistence retains the exact service/account names for
inspection. A stopped or interrupted round cannot be treated as successful.

`HostedProductCompositionTests` runs the same scenario through guarded memory
Security and the signed opt-in `KEYRECORD_HOSTED_PRODUCT_INTEGRITY_TRIAL`. The
live entry uses the actual observed session-lock provider and distributed
notifications, requires an unlocked session and uses no physical input, permission
changes, screen lock or sleep. Login-item effects remain simulated. Thus the case
does not qualify system login-item unregistration or native deletion UI behavior.

Validation at preparation: unsigned hosted build succeeds; 68 selected cases
complete with 58 passes, 10 real opt-in skips and zero failures in 7.358 seconds.
The new memory scenario records both preservation branches, restored count two,
product deletion, absent store/items and owned cleanup. Logs:
`/private/tmp/keyrecord-product-integrity-build.log` and
`/private/tmp/keyrecord-product-integrity-offline-tests.log`.

The existing standing authorization covers reviewer-checked signing and automatic
isolated verification. The bounded build reused the existing certificate and
profiles. The live round used a fresh attempt root and an explicit Keychain-only
operation allowlist. No daily store or unrelated item was targeted.
