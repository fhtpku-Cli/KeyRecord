# Synthetic live-permission recovery coverage

## Permission polling fallback — 2026-09-28 candidate

`codex/phase1-acceptance` adds a read-only Input Monitoring preflight to the
existing collecting-state monitor. A denied or unknown result closes the queue,
source, key gate and sensitive UI; restoring the fake permission alone does not
restart collection. A new product test verifies this path without emitting a tap
invalidation callback. All 46 `ProductRecoveryQuitTests` and seven
`CapturePermissionTests` passed on this candidate. It does not establish whether
macOS reports a same-process revocation through `CGPreflightListenEventAccess`,
a maximum closure time, or whether a real regrant needs a restart. No system
permission was changed for this validation.

### Owner-assisted real permission trial — 2026-09-28

The owner launched the isolated Development-signed Debug trial bundle built
from `e473a310` on native ARM. It reached Collecting after Start and consent.
The owner then turned off Input Monitoring for that trial bundle in System
Settings and reported that the App still displayed Collecting. The App was
subsequently quit normally. The owner saw no quit/reopen or other system prompt,
and the menu remained Collecting until Quit. Its private coarse interval journal
records Collecting followed by Quit, with no intervening
permission-revoked closure or Blocked transition. The run summary reports no
tap-disabled callback and no journal write failure. Aggregate input counts
exist for the run, but no per-revocation boundary was recorded, so they cannot
attribute any count to the interval after the setting changed.

This trial **does not pass** live permission-revocation acceptance. The current
evidence does not distinguish a permission preflight that stayed granted from
a monitor that stopped running or a stale UI state. Do not treat the synthetic
polling test as proof of real macOS revocation delivery. The isolated artifacts
remain private and are not copied into this repository.

The next Debug candidate records an opt-in, coarse permission witness at the
first live poll, about every four seconds thereafter, and immediately on a
non-granted result. Each witness contains only a fixed granted/not-granted
cause and the existing aggregate diagnostic fields. This diagnostic has passed
offline serialization and product compilation tests. It cannot turn a stale
macOS preflight result into a live revocation signal.

### Owner-assisted permission-witness trial — 2026-09-28

The independent Debug bundle built from `44e402d1` reached Collecting and was
quit normally. The owner's System Settings screenshot shows no entry for its
distinct display name, `KeyRecord Permission Witness Trial`; the only matching
trial entry is the earlier `KeyRecord Permission Trial`, whose Input Monitoring
switch is off. The new bundle's permission was therefore not toggled in this
run. Its private journal contains 14 periodic
`inputMonitoringPreflightGranted` witnesses, zero not-granted witnesses, and
only unstarted → collecting → stopped phase changes. No tap-disabled callback,
aggregate input delta, or journal-write failure was recorded. The Quit action
reported no live session afterward, and the process exited.

The granted witnesses show only that the collecting monitor ran while the new
bundle was collecting. This run is invalid as a live-revocation test: there was
no observed Settings entry to revoke for that bundle. It provides no evidence
about post-revocation polling, same-process closure, or the cause of the earlier
trial's continued Collecting state. Before another owner-assisted test, the
bundle identity and its appearance in Input Monitoring need to be verified.

A read-only, narrowly filtered `tccd` log review for this run attributed the
new bundle's permission request to Terminal and recorded a failed LaunchServices
lookup for the new bundle identifier. The signed bundle's Info.plist contains
the intended distinct display name and identifier, and LaunchServices now has
a record for it. The private launcher had executed the bundle binary directly;
it has been changed locally to use `open -a` with the same isolated environment.
The reusable `Scripts/launch-isolated-debug-trial.sh` now provides that launch
path for a signed trial bundle. Its `--check` mode verified this bundle's
signature, distinct identity, required-isolation marker and input arguments
without launching it. Shell syntax checking also passed. The changed launch
path has **not** been run. Its TCC attribution and Settings appearance therefore
remain unverified; no new permission trial has occurred.

### Disabled-tap liveness fallback — 2026-09-28

The product previously treated an installed dispatch signal as proof that a
capture session was live. The current candidate also checks whether its
Core Graphics tap is valid and enabled. If the tap is unavailable while the
product is collecting, the existing monitor closes protected state and leaves
the App Blocked until an explicit Start. A synthetic product test disables its
tap without delivering a callback, verifies Blocked and a closed input path,
then verifies that manual Start restores collection. The full 47-case product
recovery suite and 65 capture-layer tests passed on native ARM; the Debug App
built unsigned. An unsigned universal Release App also built and its executable
passed the existing static network audit with zero matches. This covers a
disabled tap that can be observed through
`CGEvent.tapIsEnabled`; it does not establish that macOS disables the tap on
same-process Input Monitoring revocation or that the absent witness entry now
appears in Settings. The real permission acceptance remains open.

Historical 2026-09-27 baseline: product source main
`64590a0e9b57a55af9a23921983f2c16bb59c62e`.
This follow-up adds only `testLivePermissionRevocationRequiresExplicitStartAndPreservesDurableCounts`
to `App/KeyRecordAppTests/ProductRecoveryQuitTests.swift`; no product behavior changed.

The real product composition runs against the existing synthetic host, tap, memory
Keychain and temporary encrypted store. The test:

1. Collects two bare-key counts and waits for the normal pulse to write them, without explicit flush.
2. Denies the fake permission and emits `permissionRevoked` through the source invalidation callback.
3. Waits for blocked lifecycle, no live capture, closed key gate and hidden sensitive content;
   an attempted press through the stopped tap returns closed and aggregate delta stays unchanged.
4. Tries Start while still denied and verifies capture remains closed.
5. Grants the fake permission and observes 600 ms without automatic restart or visible sensitive content.
6. Explicitly starts, verifies a live collecting session and changed queue generation,
   reads the retained disk count of two, adds one input, and waits for the normal pulse to persist three.
7. Quits through the product action and verifies one termination request.

This covers downstream product response to a delivered invalidation. It does not
prove that macOS emits that invalidation on actual permission revocation, establish
a maximum closure time, prove indefinite no-auto-restart, or determine whether
real regrant requires an application relaunch. It uses no real system permission,
global event tap or real Keychain. The stopped-tap check is not a delayed old-generation
callback injection. Existing generation-boundary tests retain their separate scope.

No real host round or additional performance measurement is required to run this test.
PR #11 remains a separate documentation/evidence change.

## Validation on 2026-09-27

- Native arm64 Debug `build-for-testing`, unsigned: passed.
- New case alone: 1 test, 0 failures (2.842 seconds).
- Entire `ProductRecoveryQuitTests` in one process: 45 tests, 0 failures (57.747 seconds).
- `git diff --check`: passed.

Logs remain locally under `.build/permission-evidence/`; no raw test store or key
material is part of this change. No SwiftPM targets or Release product code changed,
so their prior checks are not relabeled as freshly executed for this test-only change.

## Dedicated Debug trial relaunch protection — 2026-09-27

A system “Quit and Reopen” relaunched the permission trial without its environment
variables. Previously, absent trial store and namespace selected the production
composition. This establishes an unsafe fallback path, not evidence that production
records were accessed or changed in that run.

Dedicated Debug trial bundles must set the Boolean Info.plist key
`KeyRecordRequiresTrialIsolation` to `true` **before signing**. AppDelegate passes
this persistent marker to `DebugTrialIsolation.select`. Missing or blank trial
configuration then rejects startup before either composition is created. Valid
explicit isolation still selects the trial composition; partial, invalid and
production-overlapping inputs remain rejected. Unmarked ordinary Debug builds keep
their existing default. Release does not include this Debug-only selector or protection;
this marker must not be treated as Release isolation.

For a dedicated test build, copy the normal Info.plist, set a distinct bundle ID and
display name, add this Boolean marker, and supply that plist with `INFOPLIST_FILE`
when building Debug. Check the built signed bundle for the marker. Keep only one
registered launchable bundle for that test identity; duplicate build outputs can
cause LaunchServices to reopen a different copy. Retain displaced test copies
reversibly. Do not reset all LaunchServices or TCC entries.

Launch through the isolation launcher with both `KEYRECORD_TRIAL_STORE` and
`KEYRECORD_TRIAL_NAMESPACE` and normal HOME. Do not use `CFFIXED_USER_HOME`:
the earlier temporary-home approach caused a missing default Keychain prompt.
If macOS requires a restart, stop the same-process procedure. Quit the automatically
reopened trial normally and relaunch with explicit isolation. Never select a default
Keychain reset or change unrelated application permissions to make a trial proceed.

### Owner-operated bounded evidence

Signed Debug arm64 trial source: `b57dbb796056e40d7967fea34879aedff39bbf4b`
plus the three-file isolation change in this follow-up (AppDelegate, selector and
its tests). The owner observed `Startup failed: DebugTrialRejection()` on an
intentional no-environment launch. This is user-observed UI evidence, not an
automated accessibility assertion. Valid isolated launch reached collecting.

The final two isolated runs used the same trial store and Keychain item namespace:

| Observation | Result |
| --- | --- |
| Before system restart | 2 added shortcuts, published shortcut total 4, bare total 0 |
| System termination | `applicationShouldTerminate`, saved, terminate, live session false after Quit |
| Relaunch | System reopened the retained test bundle without isolation variables; owner exited it |
| Explicit isolated relaunch | Collecting; 1 new shortcut; published shortcut total 5, bare total 0 |
| Final menu Quit | 2 issued writes returned successfully and were durable; no failed, invalidated or timed-out writes; no unsaved data at Quit; process absent afterward |

The starting total includes 2 counts from an earlier preparation attempt. Thus the
observed progression is 2 → 4 → 5, not a new empty-store run. The final 4 → 5 result
is consistent with retained counts plus one new count. No independent post-exit
reload was performed. Final summaries contain a stale top-level `captureSessionLive`
value; the Quit action's `sessionLiveAfter=false` and OS process check support exit.

Local raw evidence is retained under `.build/permission-live-prep/`: no-environment
launch logs, failing-first selector tests, `session-guarded/run.8tLBOp`,
`session-guarded/run.UvtQCa`, and `restart-recovery-result.md`. These ignored artifacts
are not shipped in the repository and do not contain captured key text. Historical
code/test provenance and bounded conclusions are retained here rather than presenting
private local artifacts as downloadable PR evidence.

This round does **not** verify same-process real revocation delivery, a witnessed
revoked interval with zero input, grant-only recovery behavior, Release capture,
Intel behavior, or Phase 1/G1 acceptance. Do not repeat a whole live round merely
to obtain a green label; plan a separate bounded test only if the missing behavior
can actually be observed without macOS requiring termination.
