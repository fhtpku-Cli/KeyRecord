# Synthetic live-permission recovery coverage

**Earlier packages:** The installed 20260928b witness appeared in
Input Monitoring but failed effective data-protection Keychain access with
`-34018` before Collecting. A later arm64 PR #17 candidate compiled, but has
only an ad hoc signature and no matching embedded provisioning profile;
`launch-isolated-debug-trial.sh --check` rejected it without launching. Neither
package can validate actual revoke/regrant. Obtain a candidate that passes the
no-launch identity/profile checks and reaches Collecting before any further
permission toggle. See [current status](PROJECT_STATUS.md). The dated results
below retain their original scope.

The [2026-09-29 signing follow-up](MVP_CLOSEOUT_20260929.md) resolved the initially
missing profile in one owner-approved Xcode attempt. The trial at `de8b9c526`
is signed and passed the existing no-launch check. Its owner-approved first
consent completed key provisioning and encrypted preferences initialization;
capture startup then failed with `permissionStatus=denied`, zero sessions and
zero accepted events. It quit normally. The owner enabled permission and used
OS Quit and Reopen; the reopened instance showed blocked/privacy check and did
not write to the original journal. This is consistent with missing trial
environment on OS relaunch, not evidence of a new Keychain error. A separately
approved explicit isolated restart reused the store and namespace and reached
Collecting with `inputMonitoringPreflightGranted`. It recorded one session,
zero keyboard callbacks and zero aggregate/flush counts, then quit normally
after the controller requested termination at 55 seconds. No permission was
changed during this recovery round. It establishes isolated startup recovery;
same-process revoke/regrant remains unverified. A subsequent separately
coordinated input round, launched after an explicit ready response, recorded
3 shortcuts, 0 bare keys and 4 issued/4 durable writes before normal Quit. It
adds bounded physical-input/save evidence without exercising a permission
transition. A subsequent approved restart read back 3 shortcuts and 0 bare keys,
with no new input, writes or snapshot read failures, and quit normally within
20 seconds. These bounded startup and persistence results do not establish
same-process revoke/regrant, which remains open.

## Provisioned permission trial — 2026-09-29

After the owner explicitly confirmed readiness, the same installed signed
`de8b9c526` trial launched with its existing private store and namespace under
a 115-second normal-Quit / 120-second stop controller. It reached Collecting.
The owner was then instructed to disable Input Monitoring for that trial only,
and reported a restart or authentication prompt. The exact prompt type was not
distinguished. Per the agreed stop condition, a path-and-bundle-matched
`NSRunningApplication.terminate()` request ended the trial before the deadline;
the controller exited 0 and a subsequent process check found no KeyRecordApp.
There was no regrant, explicit Start, test shortcut or automatic relaunch.

The 66-record `privacy-permission.jsonl` observes Collecting -> Blocked at seq 6
and `protectedStateClosed` at seq 7. `captureSessionLive=false`,
`sensitiveContentVisible=false`, `privacyTrigger=sourceStopped`, and
`blockedReason=sessionLocked` are recorded. All four recorded preflight
witnesses before closure were `inputMonitoringPreflightGranted`; no denied
preflight or tap-disabled callback was observed. The source-stop trigger and
concurrent system prompt do not establish that the permission poll detected
revocation, nor that an actual screen lock occurred.

Across seq 7–66, observed aggregate/handoff/normalization/durable-write counters
remain zero; protected gate entries remain 68, snapshot attempts/publications
remain 13 and analysis attempts/publications remain 14. These finite,
non-atomic observations are partial closure evidence, not exhaustive protected
reads or continuous closure proof. The existing `PrivacyIntervalEvaluator`
returns `inconclusive / interval-not-ended` because no reauthorization end
boundary exists. The final aggregate summary retains shortcuts 3 and bare keys
0, with no new input or writes. The final system permission toggle state was
not independently verified or restored. Do not repeat toggles or claim
same-process permission recovery from this interrupted round.

## Isolated regrant/restart and rebuild race — 2026-09-29

The reason-repaired signed candidate `10676e1aa` used the same bundle identity,
private store and Keychain namespace. The first approved `--recovery` launch
failed before collection. Exact-bundle TCC preflight returned denied; read-only
System Settings inspection showed the trial's switch off and a separate
KeyRecordApp switch on. The trial quit normally with zero sessions, input or
writes. No switch was changed by the agent.

After the owner enabled the exact trial and confirmed readiness, `--recovery2`
reached Collecting with granted preflight. The owner confirmed pressing one
Command-A. The summary records one key-down/up, two modifier callbacks, four
accepted handoffs, aggregate delta 1, shortcut total 4, bare-key total 0, and one
issued/returned/successful/durable write. There were no write failures, timeouts,
invalidations or snapshot-read failures. Normal Quit at 55 seconds completed
before 60 seconds; no KeyRecordApp remained.

However, journal seq 13 records `sourceStopped` / `privacyCheckRequired` before
Quit; seq 14 closes protected state. This run establishes restored permission,
isolated startup and input/save after restart, not sustained recovery. The
23-record journal and summary are `privacy-recovery2.jsonl` and
`summary-recovery2.json` in the existing private trial root. No additional live
round was started to diagnose the unexpected stop.

A hostless regression holds a foreground-triggered session rebuild across
multiple health polls. The unmodified monitor reproducibly enters Blocked and
cannot resume, matching the observed symptom without establishing the exact
live interleaving. The repair distinguishes a health observation overlapping
reconciliation from a stable source failure, using outstanding reconciliation
calls and the capture queue's existing generation. Lock, permission and Secure
Input checks continue; stable silent stops and disabled taps still block. A
second regression revokes permission during the held rebuild and requires the
key gate and session to remain closed after it completes.

Debug build-for-testing and all 55 `ProductRecoveryQuitTests` passed after the
repair (zero failures, 63 seconds). Logs:
`/private/tmp/keyrecord-rebuild-race-{build-red,red,build-green,green}.log`.
Those offline results were followed by the separately approved host round below.

### Bounded repair confirmation at `8e3ca0c55`

After the owner explicitly confirmed readiness, the signed repaired trial ran
once using the same private store/namespace and `--recovery3` controller. The
owner confirmed one Command-A in TextEdit and returned to chat. The journal has
17 records: 15 Collecting, then two Stopped at normal Quit. There is no Blocked
phase, privacy trigger or denied-preflight witness. Three capture sessions
occurred; the rebuilding symptom did not recur during this bounded round.

The summary reports 3 down/3 up/6 modifier callbacks, 12 accepted handoffs,
aggregate delta 3, shortcut total 7, bare total 0, and 4 issued/returned/succeeded/
durable writes. Failures, timeouts, invalidations, overflow and snapshot read
failures are zero. Although the owner confirmed one Command-A, these aggregate
counters cannot identify the remaining two increments or establish exact
TextEdit/shortcut attribution. They are not reported as three Command-A presses.

Normal Quit was requested at 55 seconds; controller exited 0 before 60 seconds
without forced termination. The quit action reports `phaseAfter=stopped`,
`sessionLiveAfter=false`, saved outcome and terminate decision; a process check
found no remaining App. The summary's cached `captureSessionLive=true` is not a
post-quit liveness witness. Evidence: `privacy-recovery3.jsonl` and
`summary-recovery3.json` in the existing private root, plus
`/private/tmp/keyrecord-mvp-recovery3-controller-20260929.log`.

This completes the narrow isolated regrant/restart and foreground-rebuild
regression check for this signed candidate. Same-process revoke/regrant,
continuous closed-interval privacy, lock/sleep and full Release remain separate.

## Bounded collecting lock and explicit recovery — 2026-09-29

After approving the prepared three-minute scope and confirming readiness, the
owner completed one input, lock/unlock and explicit Start/input round on signed
`8e3ca0c55`. Identity, installed path, private store and namespace were unchanged.
The controller's `--lock` mode wrote new `privacy-lock.jsonl` / `summary-lock.json`
files. The owner performed the lock, ordinary unlock and menu actions; the agent
did not change permissions or operate authentication. No sleep was requested.

The 129-record journal opens `protectedStateClosed` at seq 13. From there to
the explicit Start action at seq 109, all 97 recorded snapshots have capture
closed and sensitive state hidden. There are 52 locked and 42 unlocked observe
records. Gate entries remain 179, aggregate delta 3, accepted handoffs 8,
normalization 6, durable writes 4, snapshot attempts/publications 37 and analysis
attempts/publications 40. Thus the sampled locked interval and unlocked wait
before Start show no new protected access, input or publication.

The Start action reports a fresh unlocked read, granted permission, readiness
`lock=unlocked,secure=disabled,foreground=attributable`, and live Collecting.
The owner confirmed the second agreed input. Final shortcut total is 9 (from 7)
and bare total 2 (from 0); the two bare increments already existed before the
closed boundary and cannot be attributed from aggregate-only evidence.
Total delta is 4, with 4 down/4 up/4 modifier callbacks, 12 accepted handoffs,
10 capture sessions and 9 issued/returned/succeeded/durable writes. Failures,
timeouts, invalidations, overflow and snapshot read failures are zero.

The controller requested normal Quit at 175 seconds, exited 0 before its
180-second stop deadline, and a process check found no remaining App. The
subsequent explicit termination helper found no matching process because the
controller had already quit it. Quit action details report Stopped, no live
session, saved and terminate; the summary's cached live flag is not teardown
evidence. Controller log:
`/private/tmp/keyrecord-mvp-lock-controller-20260929.log`.

### Diagnostic interval boundary follow-up

The unchanged evaluator reports `observed` with reason
`closed-interval-protected-gate-entry`, not a clean closed-interval result:
the old end at `captureSessionStarting` (seq 110) sees 199 gate entries, 20 more
than at the explicit Start action (seq 109). No other closed-span input/read/
publication/write counter increases. Product code reauthorizes the store after
the explicit action's fresh unlocked read, before restoring preferences and
starting capture; the marker was too late for measuring that gate's closure.

The hostless product-boundary test reproduces this before repair: gate entries
move from 32 to 44 before the old end. The Debug journal now ends with
`protectedStoreReauthorized` immediately before `gate.update(.unlocked)`, after
the current manual-recovery attempt and unlocked read have been verified. The
evaluator recognizes that precise cause separately from capture-session start.
This changes recording only, not permission checks, store authorization, capture
behavior or protection. Locked/unknown rejected Start attempts must not emit the
new end. Genuine gate entries before an end still fail the same evaluation.

Debug build-for-testing, all 55 `ProductRecoveryQuitTests`, and all 15
`ResourceEvaluationTests` pass. The new classifier test failed before the change;
it now places post-authorization reads outside the closed interval without
claiming continuous closure or every protected read. Logs:
`/private/tmp/keyrecord-lock-boundary-{build-red,red,build-green,green,evaluator-red,evaluator-green}.log`.

Original real evidence is preserved and not rewritten as PASS. The observed
lock/wait/manual-recovery behavior is supported for `8e3ca0c55`; the corrected
journal now has a separate real observation in the
[sleep round on cf08a07c](SLEEP_WAKE_ROUND_20260929.md): closed counters remain
unchanged through explicit store reauthorization. The owner missed the final
input before its deadline, so post-wake input/save remains unverified.
Continuous privacy, full hosted Keychain behavior, paused lock, sleep/wake and
Release qualification remain separate. Another owner-assisted round requires
fresh scope/readiness, not automatic replay of this one.

## Permission polling fallback — 2026-09-28 candidate

### Follow-up: generic closure reason repair — 2026-09-29

The owner later clarified that the system prompt requested Quit and Reopen,
not authentication. The next host scenario therefore covers regrant followed
by an explicit isolated restart, separately from same-process recovery. An
automatic OS relaunch still lacks the trial environment and must not be treated
as an isolated test process; the required-isolation startup check stays intact.

The mismatched `sourceStopped` / `sessionLocked` record has a reproducible
application cause: `handlePrivacyInvalidation()` assigned `sessionLocked` for
every generic privacy closure. On an unlocked injected host, the permission-poll,
disabled-tap and stopped-source tests all failed the new reason assertion before
the repair. The handler now uses `privacyCheckRequired`; actual lock handling
and a rejected explicit-start lock check still use `sessionLocked`. Capture,
key/store closure and manual-recovery behavior are unchanged. All 53
`ProductRecoveryQuitTests` and 233 Core tests passed after the repair; the Debug
test bundle built successfully. These tests repair the misleading reason, not
the still-unisolated macOS cause of the real event-source stop. Prior live
results remain bound to the older signed `de8b9c526` candidate.

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
trial's continued Collecting state. The earlier `KeyRecord Permission Trial`
entry must not be used as a substitute for the absent witness bundle. No further
owner-assisted permission trial is scheduled from this result.

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

After the cycle-reset repair at product source `648144555b0bee70b819148f381de1d6aacbb54c`, a fresh arm64 Debug witness App was built from PR head `2f117e5433654f89fa01f826e92e9cfbc7ac58c4`. Its signed bundle ID is `com.keyrecord.trial.permissionwitness20260928`, its display name is `KeyRecord Permission Witness Trial`, and its mandatory trial-isolation marker is true. `codesign --verify --strict --deep` passed with the existing Apple Development identity. The actual Debug product dylib has SHA-256 `d44b62ed4f536dabfe8e938290501506fdd29a839e74d236118033891434623e`. The signed App was registered with LaunchServices after its plist was finalized; the current path's LaunchServices record now shows that display name and bundle ID. A private wrapper at `/private/tmp/keyrecord-permission-witness-current.WIhdZF/launch.sh` requires an explicit `--run`; its `--check` mode passed without launching, and invocation without a mode exits with usage status 2. No current App process was running after preparation. This establishes current-candidate build, signature, identity and LaunchServices registration only. The App has not been launched, no TCC permission was changed, and its Input Monitoring Settings appearance remains unverified.

The owner then ran that package once and reported no `KeyRecord Permission Witness Trial` entry in Input Monitoring. Its isolated journal contains Start, first consent and menu Quit, but no Collecting session: 50 records show Failed / `keyUnavailable`, `sessionCount=0`, and all aggregate and flush counts are zero. First-consent provisioning ended in `keyProvisionFailed(LifecycleKeyError.unavailable)` before capture readiness. A narrow system-log review identified two concrete packaging faults. `secd` rejected the trial's data-protection Keychain add with OSStatus `-34018` because the manually re-signed App lacked an application identifier or Keychain access-group entitlement, even though ordinary `codesign --verify` passed. `tccd` attributed the ListenEvent status query to the correct trial bundle, but a subsequent LaunchServices lookup for that bundle ID returned `-10814`; the App was still located under a temporary build directory. This run did not exercise revocation, recovery or input collection.

A replacement Debug package was built with `com.apple.application-identifier` embedded during Xcode signing and a fresh bundle ID `com.keyrecord.trial.permissionwitness20260928b`. It was copied to the user's Applications directory and registered there. The installed App's strict deep signature check passed; its embedded application identifier matches the bundle ID, its trial-isolation marker is true, and LaunchServices and Spotlight both resolve the installed bundle. The launcher's `--check` rejects the previous missing-entitlement package with exit 2 and accepts the replacement package without starting it; Shell syntax checking passed. Those checks were preparation evidence only; the runtime result follows.

The owner launched that replacement once. System Settings showed `KeyRecord Permission Witness Trial 20260928b` with Input Monitoring off. Enabling it required Quit and Reopen; the reopened App showed the generic blocked/privacy-check title. The original isolated process's journal ended at normal Quit: its Start saw `permissionStatus=denied` and `preferencesLoadFailed(LifecycleStoreError.protectedDataUnavailable)`, with `sessionCount=0`, no Collecting phase, and zero aggregate delta. The automatic relaunch produced no entry in that isolated journal. The trial-isolation marker rejects a launch without the wrapper's environment before product composition; the generic blocked title alone cannot identify the exact startup cause.

A narrow `secd` review at the first process's Keychain call showed that macOS **ignored** `com.apple.application-identifier` because of an invalid application signature or incorrect provisioning profile, then returned OSStatus `-34018` for `SecItemCopyMatching`. Thus the embedded entitlement and successful `codesign --verify` were insufficient to establish effective Keychain access. The Input Monitoring entry proves Settings discoverability for the installed package, but this round never reached Collecting or a same-process revoke/regrant interval. No further permission toggle is justified by this package result; real permission recovery remains unverified.

The reusable isolated Debug launcher now also requires an embedded provisioning profile whose Team ID and exact or wildcard App ID authorize the signed trial identifier. `bash -n` passed, and `--check` rejected the installed 20260928b package before launch with exit 2 because it has no embedded profile. This closes the specific preflight false acceptance from that package; a matching profile still does not prove macOS will grant runtime Keychain access. Do not ask for another permission toggle until a new package has passed a bounded effective-access check and actually reached Collecting.

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

### Silent event-source stop fallback — 2026-09-28

A hostless product reproduction stopped the event source without an invalidation
callback while the lifecycle was Collecting. Before the repair, the collecting
monitor left the product in Collecting for the full eight-second test timeout.
The monitor now treats a stopped source as a privacy failure when Secure Input
is disabled and the lifecycle expects it to be disabled. It closes protected
state and requires an explicit Start; the existing Secure Input recovery path
still handles an intentionally stopped source while Secure Input is active.
The reproduction passed after the change, and all 52
`ProductRecoveryQuitTests` passed on native ARM. This closes an offline
status/liveness fault. It does not prove that macOS reports a same-process Input
Monitoring revocation or that the Settings switch takes effect before restart.

The macOS SDK's `IOKit/hidsystem/IOHIDLib.h` describes
`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` as a check for
IOHIDManager/IOHIDDevice access. This product observes a Core Graphics
event tap and already polls `CGPreflightListenEventAccess()` plus the tap and
source state. The HID API's documented scope does not establish that it would
notice this tap's same-process permission revocation sooner. No new permission
probe was added on that assumption; the signed candidate must first show an
effective Keychain identity and reach Collecting, then a bounded host observation
can determine what macOS actually reports after revocation.

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
