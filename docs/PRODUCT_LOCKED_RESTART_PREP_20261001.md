# Existing-store process restart under lock: preparation

The preceding [fresh-install locked-startup round](PRODUCT_LOCKED_STARTUP_PREP_20260930.md)
passed on its signed source, with a retained runtime warning. Its same-process
reconstruction did not prove restoration in a new process. This scenario adds
separate seed and restart XCTest entry points within the existing passive host.
No production source changes, global input capture or permission toggles are involved.

## Executable scenario

The opt-in is `KEYRECORD_HOSTED_LOCKED_RESTART_TRIAL=1`. Both stages require the
existing signed manifest to authorize exactly Keychain, screen lock/unlock and
restart. They retain fresh per-operation signing/namespace checks.

1. `testAuthorizedProductRestartSeed` requires observed unlock, a new random
   namespace and unused `restart-store`. It checks exact namespace absence,
   constructs the actual product with the real lock provider, accepts fixture
   consent, saves two fixed simulated inputs and stops the product. It records
   the namespace seed, seed PID and successfully created account names in a
   private JSON file. The file contains no key material or ordinary input.
2. After that host exits, the controller must wait for a separately coordinated
   lock before launching `testAuthorizedProductRestartWhileLocked`. The test
   rejects the original PID, incomplete seed records, unexpected accounts,
   nonregular records and unlocked startup. It constructs the product against
   the same store with zero Keychain pre-reads. While locked it requires closed
   capture/presentation, rejected fixed input, bounded zero counter deltas and
   zero guarded client operations.
3. After observed unlock, explicit Start/Retry restores two committed counts,
   then one fixed input makes three. It stops the product and deletes only the
   two recorded items, verifying their absence. The controller must confirm
   termination and inspect both XCTest results before claiming process recovery.

`master-v2` is allowed for the backend's exact next-version inventory query;
it is not adopted for cleanup unless actually created. This fixture expects only
`metadata` and `master-v1` to be created. Unexpected ownership prevents seed success.

## Failure handling

Successful additions are tracked in memory before ownership persistence. A write
failure propagates; the seed failure path retries recording the actual owned
accounts, leaves the completion field unset and logs the exact service/account
names. If locked, it explicitly defers cleanup without Keychain calls. If both
record writes fail, the retained seed log is the recovery evidence; inspect those
actual successful identities before a separately reviewed exact cleanup. Never
delete all allowed accounts or treat an incomplete seed as a successful restart.

If a completed seed is interrupted before recovery, the dedicated
`testAuthorizedProductRestartCleanup` can remove its two recorded items. It
requires a new process, observed unlock and the same current authorization.
Missing authorization, unknown/locked state or an incomplete record blocks this
entry point. A stopped/expired controller must retain evidence for reviewed
recovery, not launch an unapproved cleanup or silently report a clean namespace.

## Offline verification

Native unsigned Debug test compilation succeeds. The three selected hosted
classes run 27 cases: 21 pass, six real opt-ins skip, zero failures (6.867 seconds).
The new memory-backed reconstruction observes zero locked client attempts and
restores two before saving three. Record tests reject incomplete/same-process,
unowned-account and symlink records; an injected ownership-write error preserves
successful-add tracking for exact cleanup. This remains same-process simulated
evidence, not a signed separate-process or physical lock result.

The initial run failed because the fixture omitted `master-v2` from the permitted
inventory reads. Product `LocalKeychainBackend.versions` correctly probes the next
version. Restoring that exact query allowance resolves the focused case in 0.188
seconds; the product and cleanup ownership were not weakened.

Logs in `/private/tmp`: `keyrecord-locked-restart-build-20261001.log`,
`keyrecord-locked-restart-tests-20261001.log` (initial failure),
`keyrecord-locked-restart-inventory-test-20261001.log`,
`keyrecord-locked-restart-final-build-20261001.log` and
`keyrecord-locked-restart-final-tests-20261001.log`.
Independent review: `/private/tmp/.omo/evidence/locked-restart-ownership-rereview-code-review.md`.

Signing and a reviewed bounded controller must precede physical readiness.
The real two-process scenario has not run. Even a pass will not establish raw
locked-state Keychain accessibility, public lock-API support, exhaustive privacy
coverage, rendered UI or a qualified collecting Release.
