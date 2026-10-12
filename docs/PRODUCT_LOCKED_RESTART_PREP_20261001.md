# Existing-store process restart under lock: bounded signed result

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round.

## Current result: PASS

The coordinated real round on signed `0766c515b51e21aedd96f6dab32377eb8bdfcf3d`
completed on 2026-10-01. The owner confirmed seeing the lock screen and unlocking.
Both selected XCTest cases passed with zero failures/skips and empty xcresult
runtime-warning arrays. The seed case took 3.109 seconds; the restart case took
27.200 seconds. Controller stage durations were 7.729 and 28.892 seconds, with
53.383 seconds for the whole round including the lock readiness wait.

Seed PID 40935 saved two fixed simulated counts and exited. The controller then
recorded consistent eligible/locked session and console witnesses before starting
PID 41230 against the same encrypted store. The new process made zero guarded
product Keychain attempts while locked; after observed unlock it restored two
committed counts and saved a third. Both owned Keychain items were deleted with
verified absence. Both hosts exited normally, no forced stop or control error was
reported, and a later presence check found neither an exact nor foreign probe.

Evidence in `/private/tmp/keyrecord-product-locked-restart-20261001` includes
`round.json`, `launch-lock-state.json`, the private ownership record,
`seed-run.json`, `restart-run.json`, both logs and both `.xcresult` bundles.
This closes the bounded actual separate-process existing-store recovery scenario
on this signed Debug host. Input is synthetic; permission/foreground/Secure Input
are fixed providers. The lock inputs and Keychain/store are real. It does not
promote private lock fields to a production support guarantee or qualify Release.
The earlier startup case's runtime warning remains in its historical result;
this round's two cases have no recorded runtime warnings.
Independent actual-result review is
`/private/tmp/.omo/evidence/locked-restart-live-result-code-review.md` (PASS).

## Original preparation

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

## Signed preparation

Source `0766c515b51e21aedd96f6dab32377eb8bdfcf3d` was built using existing signing
profiles/certificate in `/private/tmp/keyrecord-product-locked-restart-20261001`.
The reviewed signer finished in 22.030 seconds, exit 0, without forced stop,
remaining build process group, installation or App launch. It did not request
new signing material. Its synthetic timeout/error/cancellation tests pass.

Controller: `/private/tmp/keyrecord-product-locked-restart-round.py`.
Exact-path helper: `/private/tmp/KeyRecordLockedRestartControl`.
The preparation-only `--check` passes for the exact source and three selected
entry points, with no host launch, manifest write or real Keychain calls.
The presence helper reports no exact or foreign probe. Sandbox trust inspection
returned `CSSMERR_TP_NOT_TRUSTED`; the same strict inspection passed in the normal
system environment. This was not a failed signed execution or an entitlement fix.

Independent review caught insufficient worst-case termination time in the first
controller draft. The stage force deadline is now at most 120 seconds from the
start of the whole round, retaining up to 60 seconds for slow termination helpers,
confirmation and result inspection. Cancellation is checked before each host
launch; cleanup is forbidden while locked/unknown or after cancellation. The
synthetic suite covers failed seed, readiness failure with unlocked cleanup,
locked deferred cleanup, cancellation, skipped seed results and a helper consuming
five seconds per call. Its sequencing and termination tests pass. Actual source
and observer tests use fixed synthetic inputs; these controller tests call no
real Keychain operations.

Independent re-review and its repeated synthetic/actual preparation checks pass:
`/private/tmp/.omo/evidence/locked-restart-controller-rereview-code-review.md`.
The exact host and plugin signing permissions were also checked. No real host or
Keychain operation ran during that review.

The next step requires owner readiness, not another
signing approval. Start unlocked; the controller first saves two simulated counts
and exits the seed host. Only after the explicit lock instruction should the owner
lock, wait about 20 seconds, then unlock. No ordinary test keys, permission toggles,
App consent clicks or sleep are involved. Keep the entire coordinated round within
three minutes; stop and retain evidence if either stage or cleanup is unresolved.

The preparation above preceded the passing round recorded at the top. It does not establish raw
locked-state Keychain accessibility, public lock-API support, exhaustive privacy
coverage, rendered UI or a qualified collecting Release.
