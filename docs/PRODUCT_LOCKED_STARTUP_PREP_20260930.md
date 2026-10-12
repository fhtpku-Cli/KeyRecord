# Product startup while locked: bounded signed result

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round.

## Current result: functional PASS with a retained runtime warning

Signed source `3174772037ac18e40a822e0bab12f278f41486b8` completed the
owner-coordinated round on arm64 macOS 27.0 (26A428). The owner confirmed seeing
the lock screen before unlocking. The controller recorded consistent locked
session/console observations before launching the actual signed product host.
The selected case passed in 26.905 seconds: one passed, zero failed or skipped.
It recorded zero guarded product Keychain attempts while locked, then saved two,
restored two and saved three after unlock. Both created items were deleted and
their absence checked. The controller exited normally in 31.281 seconds after
launch (49.889 seconds including readiness), with no force, control errors or
remaining exact host. A subsequent presence check found no probe instance.

The xcresult retains one Security runtime-warning entry: a method should not be
called on the main thread. This is a functional PASS, not a warning-free result.
The test entry performed synchronous signed-resource preparation on MainActor;
the subsequent source repair removes that entry annotation while retaining
MainActor isolation for product operations and per-operation authorization.
The signed artifact above predates that repair; removal of the warning in a new
signed execution is not claimed. No repeat physical round is required solely
for this warning.

The source repair builds successfully without signing. The three selected hosted
classes then execute 21 cases: 18 pass, three real opt-ins skip, zero failures
(6.706 seconds). Logs are `/private/tmp/keyrecord-locked-startup-offmain-build.log`
and `/private/tmp/keyrecord-locked-startup-offmain-tests.log`. This validates the
fixture regression paths; skipped live cases do not prove warning removal in a
signed run. Existing headermap build warnings remain.

Evidence: `/private/tmp/keyrecord-product-locked-startup-20260930/` contains
`launch-lock-state.json`, `keychain-run.json`, `keychain-run.log` and
`keychain.xcresult`. Independent result review is
`/private/tmp/.omo/evidence/locked-startup-live-result-code-review.md`.
This closes the bounded fresh-install product startup-under-lock scenario only.
Existing-store separate-process restart under lock, raw locked Keychain behavior,
production lock authority and collecting Release remain open.

## Original preparation and scope

The [owner-coordinated source observation](LOCK_STATE_SOURCE_PREP_20260930.md)
recorded fresh diagnostic processes across unlocked/locked/unlocked states.
The scenario starts the actual signed test host while already locked and
assembles the product with `SystemSessionLockProvider` and real distributed
notifications. Event input, permission, foreground and Secure Input remain fixed
test inputs; there is no global event tap or ordinary input capture.

## Executable scenario and boundaries

The distinct opt-in is `KEYRECORD_HOSTED_LOCKED_STARTUP_TRIAL=1`; the exact case is
`KeychainLifecycleTests/HostedProductCompositionTests/testAuthorizedProductStartupWhileLocked`.
Its existing signed manifest must authorize exactly Keychain test items and the
coordinated screen-lock/unlock operation. It keeps a new private store and random
namespace, recording only the service string for cleanup recovery.

The fixture requires an observed locked state before product construction. It
checks closed queue/key access, hidden protected presentation model, rejected
fixed input, a bounded zero-read/publication/aggregate observation, and zero
attempted product Keychain operations through the guarded client. Namespace
absence queries occur only after observed unlock. They must not precede or
contaminate the locked-startup zero-read assertion.

After unlock the fixture explicitly performs Retry to load the store. Before a
separate Start/consent action, it requires unstarted state, no preferences/failure,
the actual fresh-install load classification and no created items. It then saves
two simulated counts; a new composition in the same process restores two and
saves a third. Cleanup removes and checks absence of only successfully created
items. Failure retains the service record; cleanup failure fails the test.

The product's existing two-step Retry then Start/consent behavior is preserved.
The first fixture incorrectly assumed one action would reach consent. The failing
diagnostic established `unstarted`, no failure and no owned items after Retry.
The correction makes both actions explicit and verifies successful fresh loading;
it does not bypass failed loading or change product code.

This scenario is fresh-install product startup under a real lock followed by
unlocked saving and same-process reconstruction. It is not an existing-store
process restart under lock, raw locked-state Keychain accessibility measurement,
exhaustive/continuous protected-read proof, rendered UI or collecting Release
qualification. The observer transition labels do not constitute an independent
OS authority. The private lock fields remain subject to the documented support
question; `qualifiedLiveVersions` remains empty.

## Offline result

- Unsigned native Debug test build passes.
- The focused corrected memory-client scenario passes in 0.212 seconds, with zero
  Keychain attempts while locked, counts 2/2/3 and two owned items cleaned up.
- All three selected hosted classes pass: 18 offline cases, zero failures and all
  three real Keychain opt-ins explicitly skipped (21 selected cases, 6.803 seconds).
- The original simulated scenario still requires phase `blocked`; its existing
  assertion was retained when closed-state waiting was shared with fresh startup.
- The first direct XCTest invocation failed to load the host debug dylib. Setting
  the compiled host's `DYLD_LIBRARY_PATH` resolved this setup issue. The original
  load failure, fixture failure and final passing logs remain separate.

Logs under `/private/tmp`: `keyrecord-locked-startup-offline-build.log`,
`keyrecord-locked-startup-offline-tests.log` (load failure),
`keyrecord-locked-startup-offline-tests-loaded.log` (fixture failure),
`keyrecord-locked-startup-diagnostic-tests.log` (specific state),
`keyrecord-locked-startup-retry-build.log`,
`keyrecord-locked-startup-retry-tests.log` and
`keyrecord-locked-startup-final-tests.log`.

## Prepared execution sequence

Complete independent source review and a bounded signed build using existing
profiles/certificate, with no provisioning updates, installation or host launch.
Inspect the resulting exact artifact and review the controller before coordinating
the physical round. The owner has standing authorization for reviewed signing and
automated checks; the physical window still waits for explicit readiness.

The controller will first wait at most 60 seconds for consistent locked-state
observations in fresh diagnostic processes. Only then may it launch the test host.
The test independently rejects an unlocked start. After the owner locks, allow
about 20 seconds before normal unlock, then report whether the lock screen was
visible. The test waits at most 60 seconds for unlock. Host control requests normal
exit at 85 seconds after launch and forces only the exact trial host at 90 seconds.
The overall controller window is bounded by about 150 seconds plus preparation;
no sleep, permission toggles, manual test keys or installation are needed.

No signed build or physical product locked-startup run is claimed by the offline
results above. Preserve the current restriction until its exact result is inspected.

## Signed preparation result

Source `3174772037ac18e40a822e0bab12f278f41486b8` was built using existing profiles
and certificate in `/private/tmp/keyrecord-product-locked-startup-20260930`.
The reviewed signing controller finished in 27.617 seconds with exit 0, no forced
stop, no remaining build process group and no App launch. Independent review
verified the host/plugin signatures, permissions and existing profiles. No
provisioning update or installation occurred.

The private controller is `/private/tmp/keyrecord-product-locked-startup-round.py`;
its exact-path host helper is `/private/tmp/KeyRecordLockedStartupControl`.
Review found a cancellation race in the new readiness wait. It now rejects stop
requests after each lock-state read, after preflight and before `Popen`; synthetic
tests cover a stop arriving inside the read and forbid any subsequent launch.
The complete synthetic controller self-test passes. The host budget also reserves
15 seconds of the overall 180-second window for termination confirmation.
Swift helper compilation and Python syntax validation pass without installing LSPs.
The controller's actual `--check` passes for the exact signed source and selected
test, reporting no host launch, no manifest write and zero real Keychain calls.
The independent presence helper reports no exact or foreign probe instance.
The reviewer reran the synthetic suite and cleared the cancellation fix in
`/private/tmp/.omo/evidence/locked-startup-controller-rereview-code-review.md`.

The preparation above preceded the physical round. Its later bounded result is
recorded at the top; static signing checks alone did not establish that result.
