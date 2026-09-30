# Product key integrity and deletion

Status: offline fixture passes; real Keychain execution is not yet performed.

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
isolated verification. The next bounded build reuses the existing certificate and
profiles; no new signing material or account interaction is requested. The live
round will be measured separately with a fresh attempt root and an explicit
Keychain-only operation allowlist. No daily store or unrelated item is targeted.
