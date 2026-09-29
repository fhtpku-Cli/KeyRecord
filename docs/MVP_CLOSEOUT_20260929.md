# Apple Silicon MVP closeout checkpoint — 2026-09-29

Performance checkpoint: replacement typing and idle on signed `a604ad535` with
controller `1cf51a056` both completed and exited normally. Host evaluation is
within-budget: CPU 0.0983% typing / 0.0807% idle, highest footprint mean/peak
33.93/34.06 MB. Typing saved 2,550 key downs; all 145 writes succeeded durably.
No process remains. The short native ARM measurement is complete; productPass
remains false because this is candidate-specific Debug fixed replay, not full
MVP/Release qualification. The original invalid window is retained separately.
See [the current round](PERFORMANCE_SHORT_ROUND_20260929.md).

Performance protocol update: formal acceptance now uses one typing and one idle
window, each 30 seconds warmup plus 120 seconds measurement. The previous
six-window/hour-long default is superseded at the owner's request; thresholds,
sample validity, durability and privacy checks remain. Targeted reruns only.
See [the current protocol](PHASE1_ACCEPTANCE.md#performance-plan); historical
long-window evidence below retains its original scope.

Earlier result: the approved [second sleep/wake round](SLEEP_WAKE_SECOND_ROUND_20260929.md)
on signed `cf08a07c` observed 32.028 seconds suspended, unchanged sampled closed
counters through wake, explicit Start restoring Collecting and new post-recovery
input/save. Normal early Quit at 223.431 seconds left no process. Final totals
are 12 shortcuts/2 bare keys; all 12 writes succeeded durably. The repaired
diagnostic boundary reports observed. This closes the narrow bounded scenario,
not full continuous privacy/Keychain/Release qualification. The first partial
sleep round and lock round on `8e3ca0c55` retain their original results.

Status: offline validation and provisioned trial preparation passed; collecting
MVP still awaits product-host qualification. The preparation below did not launch,
install or register a product App, or operate a real Keychain item, TCC setting,
lock/sleep state or daily statistics store.

## Candidate and scope

Product source tested: `ba57ea711e86de37b92c89c46dc6975b557fa69d`, branch
`codex/phase1-acceptance`, draft PR #17. The accompanying changes add only an
isolated build helper, its plist/entitlement templates, and documentation; they
do not change product Swift source or the normal Xcode project settings.
The primary checkout was not modified. Intel runtime/performance and packet
capture were not part of this work.

## Observed results

| Check | Result | Local evidence |
|---|---|---|
| `Scripts/verify-local.sh --build-only` | PASS: 546 SwiftPM tests; 19 harness CLI cases and 6 offline fixture checks; SwiftPM Release, unsigned universal App Release, native arm64 Debug test build | `.build/verification/run.NXqnQJ/` |
| Hostless App XCTest, selected suites below | PASS: 133 tests, zero failures, zero skips; includes 53 recovery tests and the Release-binary-dependent isolation test | `/private/tmp/keyrecord-closeout-app-tests-20260929.log` |
| `swift test --package-path Spikes/KeychainLifecycle` | PASS: 40 hosted-controller logic tests and 82 preflight tests; injected backends only | `/private/tmp/keyrecord-closeout-keychain-20260929.log` |
| `Scripts/audit-product-network.sh` against the Release executable from the first row | PASS: 1,854 undefined-symbol lines, 20,192 string lines, zero matches, `liveReceipt=false` | Exact binary: `.build/verification/run.NXqnQJ/release/Build/Products/Release/KeyRecordApp.app/Contents/MacOS/KeyRecordApp` |
| Initial signing build through the new helper | BLOCKED: Xcode exit 65, no matching Mac App Development profile; no App launched | `/private/tmp/keyrecord-closeout-script-20260929/build.log` |
| Owner-approved Xcode provisioning follow-up | PASS: matching profile generated, signed arm64 Debug built at `de8b9c526`, existing launcher's signature/profile check passed; no launch | `/private/tmp/keyrecord-mvp-profile-attempt-20260929/build.log` |
| Unsigned build using the new trial templates | PASS: arm64 loader and product dylib; expected bundle ID/display name and Boolean isolation marker | `/private/tmp/keyrecord-closeout-unsigned-trial-20260929.log` and adjacent DerivedData directory |
| Existing launcher `--check` on that unsigned trial | Correctly rejected, exit 2: embedded provisioning profile missing | Trial build above; no launch |
| Build helper CLI | `--help` exits 0; six invalid invocations exit 2 before creating output; existing output is refused; Bash syntax and both plists validate | Commands and cases below |

The package suite totals are Store 173, Measurement 19, Integration 42, Core 233,
Capture 67, Analysis 12. The Integration suite includes the six privacy source
and binary-audit tests with negative fixtures. The App suites are
`LocalKeychainQueriesTests` (6), `Phase1FlowHostlessTests` (14),
`Phase1ReleaseIsolationTests` (22), `ProductLocaleStartupTests` (4),
`ProductLocaleTransactionTests` (3), `ProductRecoveryQuitTests` (53),
`ProductReductionTests` (9), `ProductReleaseBoundaryTests` (11), and
`ProductWiringTests` (11). Expected rejection messages in the boundary fixtures
are not test failures. No native screen or VoiceOver qualification is implied.

Both GitHub macOS build jobs passed for the tested starting commit:
[push workflow](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36468906111)
and [PR workflow](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36468910969).
Later commits require their own CI results.

## Signing finding and reproducible preparation

A sandboxed `security find-identity -v -p codesigning` returned zero identities.
The same read-only command outside the sandbox found one valid Apple Development
identity. Therefore **a missing certificate is not the established blocker**.
Neither standard local provisioning-profile directory existed. A real Xcode
build requesting the data-protection Keychain entitlements returned:

```text
No profiles for 'com.keyrecord.trial.mvp20260929' were found:
Xcode couldn't find any Mac App Development provisioning profiles matching
'com.keyrecord.trial.mvp20260929'.
```

This agrees with Apple's explanation that the data-protection Keychain access
entitlements must be authorized by a profile: [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).
The owner then approved one attempt, bounded to two minutes, using the existing
Xcode account with `-allowProvisioningUpdates`. That actual attempt exited 0:
Xcode generated `Mac Team Provisioning Profile: com.keyrecord.trial.mvp20260929`,
built the arm64 Debug App and embedded the profile. The signed identifier is
`com.keyrecord.trial.mvp20260929`, Team ID `P3W62C39TN`; the existing launcher's
`--check` passed. This resolves the local provisioning blocker. Runtime Keychain
access is still unverified; no product launch was included in that authorization.

The new helper uses Xcode signing with the requested application identifier,
team identifier and exact Keychain access group. It neither manually re-signs
the finished bundle nor changes the ordinary project defaults. It calls the
existing launcher's `--check` only after a successful build. Its output folder
is new and private; the Info.plist permanently requires explicit trial isolation
on relaunch. It does not pass `-allowProvisioningUpdates`.

From the isolated worktree, after matching signing assets are available:

```sh
bash Scripts/build-isolated-debug-trial.sh \
  com.keyrecord.trial.mvp20260929 P3W62C39TN \
  /private/tmp/keyrecord-mvp-provisioned-next
```

The output path must not already exist and its parent must exist. An optional
fourth argument selects an already installed profile UUID with manual signing.
The actual blocked run used `/private/tmp/keyrecord-closeout-script-20260929`.
The unsigned template check used the same `INFOPLIST_FILE` and
`CODE_SIGN_ENTITLEMENTS` with `CODE_SIGNING_ALLOWED=NO`; that check is deliberately
not exposed as a collecting-candidate option in the helper.

CLI rejection cases exercised: missing arguments, production bundle ID, malformed
Team ID, existing output directory, relative output directory, malformed profile
UUID. Syntax: `bash -n Scripts/build-isolated-debug-trial.sh`; plist validation:
`plutil -lint Scripts/fixtures/isolated-debug-trial/Info.plist Scripts/fixtures/isolated-debug-trial/Trial.entitlements`.
The Bash language server is not installed; no LSP result is claimed.

## Approved first-consent trial and remaining work

The provisioned candidate is at
`/private/tmp/keyrecord-mvp-profile-attempt-20260929/build/Build/Products/Debug/KeyRecordApp.app`,
source `de8b9c526da7606438ace3a78efd5afc5b6c2081`. The general-purpose launcher
alone has no timer. A local bounded controller was therefore compiled from
`/private/tmp/keyrecord-mvp-profile-attempt-20260929/BoundedTrial.swift`.
Its `--check` passed against this candidate and the empty owned 0700 directory
`/private/tmp/keyrecord-mvp-readiness-20260929`; it made no launch. The controller
requests normal Quit at 55 seconds and forced termination of its trial instance
at 60 seconds if needed. The first trial exited before the deadline; the timed
normal-Quit and forced-stop branches were not exercised by that run.

The owner separately approved installation at
`~/Applications/KeyRecord MVP Trial 20260929.app`, first consent/Start with that
private root and the `com.keyrecord.trial.mvp20260929` Keychain namespace, and
only three Command-A shortcuts after Collecting. The installed signature passed;
LaunchServices registration completed. The original trial process produced 32
journal records and a normal Quit summary at the root above. Its accept action
ended with `captureStartDenied(LifecycleCaptureError.runtimeFailed)` and
`permissionStatus=denied`. It never entered Collecting: `sessionCount=0`,
`handoffAccepted=0`, `normalizationOutput=0`, `aggregateDelta=0`,
`flushIssued=0`, and `flushDurable=0`.

First-consent key provisioning and encrypted preferences initialization completed
before that failure: the lifecycle reached capture startup, and the fresh store
contains its encrypted manifest and two encrypted objects. This is product-path
evidence for initial protected storage, not exhaustive Keychain CRUD, lock
accessibility, collected-count durability or lifecycle qualification.

The owner reported the Input Monitoring request, enabled it, and used macOS
Quit and Reopen; the reopened menu said blocked/privacy check. The original
isolated journal had already ended, so it does not identify the reopened
process's failure. Missing isolation environment on OS relaunch is consistent
with the existing fail-closed startup code; it is not another observed `-34018`.
An attempted native AX read failed with `Sky Computer Use native pipe closed
before response`, so no screen or accessibility PASS is claimed. A later process
at the exact installed trial path was found and stopped after the approved
deadline. Whether the OS reopen or the failed UI binding started it was not
established. A subsequent process check found no KeyRecordApp instance.

The controller now has a separately checked recovery mode that reuses only this
known trial root and namespace and writes `privacy-reopen.jsonl` and
`summary-reopen.json`, preserving the first run. It compiled with Swift 6 and
`-parse-as-library`; the standalone SourceKit diagnostic about `@main` lacked
that build mode, while the actual compiler succeeded. `--resume-check` passed
without launching. The owner subsequently approved exactly one recovery round
with the same root, namespace and signed candidate; no further permission
changes, lock/sleep or ordinary data were included.

That round ran through `BoundedTrial --resume`. Its controller log is
`/private/tmp/keyrecord-mvp-resume-controller-20260929.log`; the preserved root
contains `privacy-reopen.jsonl` (17 records) and `summary-reopen.json`. The
journal starts in Collecting and witnesses `inputMonitoringPreflightGranted`.
The summary records `sessionCount=1`, `snapshotPublicationCount=51`,
`analysisPublicationCount=52`, and `snapshotReadFailureCount=0`. Reusing the
existing encrypted store reached startup recovery without a new consent action
or key-provisioning request. This is bounded real product startup evidence.

All three keyboard callback counters, `handoffAccepted`, `normalizationOutput`,
`aggregateDelta`, published shortcut/bare-key totals, `flushIssued` and
`flushDurable` are zero. The owner subsequently reported missing the prompt to
perform the agreed shortcuts. The coordinated input step was not completed;
this round cannot diagnose an event-delivery failure or establish physical-input
or durable-count acceptance. Before any future owner-assisted timed round, pause
and wait for an explicit ready response before launching or starting the clock.

The controller requested normal Quit at 55 seconds and exited 0 before the
60-second forced-stop deadline. The journal records `phaseAfter=stopped`,
`sessionLiveAfter=false`, `quitDecision=terminate` and no unsaved reduction or
scheduler data. The summary's cached `captureSessionLive=true` is not an atomic
post-quit observation; the action detail and an outside-sandbox process check
(no `KeyRecordApp` remained) establish teardown. The forced-stop branch was not
exercised. No additional launch was performed within that recovery approval.

## Coordinated physical-input round

The owner asked to continue. The local controller gained a separate `--input`
mode preserving both earlier runs and writing `privacy-input.jsonl` and
`summary-input.json`. Actual Swift 6 compilation with `-parse-as-library` and
`--input-check` passed without launching. After the owner explicitly replied
ready, this one round launched the same installed, signed `de8b9c526` candidate
with the existing trial root and Keychain namespace. The agreed interaction was
three Command-A shortcuts in blank TextEdit after Collecting. No permission,
lock/sleep or ordinary-data operation was included.

The controller log is `/private/tmp/keyrecord-mvp-input-controller-20260929.log`.
The trial root's input journal has 17 records. Aggregate summary results:

| Observation | Result |
|---|---:|
| Key-down / key-up / modifier callbacks | 3 / 3 / 6 |
| Accepted handoffs / normalization output | 12 / 6 |
| Aggregate delta / published shortcut total / bare-key total | 3 / 3 / 0 |
| Issued / returned / successful / durable writes | 4 / 4 / 4 / 4 |
| Failed / timed-out / invalidated writes | 0 / 0 / 0 |
| Handoff overflow / tap-disabled events / snapshot read failures | 0 / 0 / 0 |

Collecting and granted Input Monitoring were observed. The controller requested
normal Quit at 55 seconds and exited 0 before 60 seconds. The quit action records
`phaseAfter=stopped`, `sessionLiveAfter=false`, `quitDecision=terminate` and no
unsaved reduction/scheduler data. An outside-sandbox process check found no
remaining KeyRecordApp. As in the preceding run, the summary's cached live flag
is not a post-quit process witness. Forced stop was not exercised.

This establishes bounded physical input through aggregation and reported durable
save on the signed Debug candidate. The summary contains no per-application or
shortcut identity rows; it cannot independently establish TextEdit attribution
or the exact Command-A row. At that checkpoint no new process had read back the
three saved counts; the separately approved follow-up below adds that evidence.
No broader privacy or Release result is inferred.

## Bounded restart readback

The owner requested continuation and explicitly confirmed readiness after a
20-second restart round was prepared. The local controller's `--readback` mode
passed actual Swift 6 compilation with `-parse-as-library` and the no-launch
`--readback-check`. It preserved prior artifacts and reused the same installed
signed `de8b9c526` candidate, private root, encrypted store and Keychain namespace.
The owner was asked to refrain from pressing keys during this round. No
permission change, lock/sleep operation or ordinary-data access was included.

Controller log: `/private/tmp/keyrecord-mvp-readback-controller-20260929.log`.
The trial root contains `privacy-readback.jsonl` (9 records) and
`summary-readback.json`. A new process reached Collecting and published shortcut
total 3 and bare-key total 0. All keyboard callback counters, accepted handoffs,
normalization output, aggregate delta, issued writes and durable writes were
zero. It published 15 snapshots with zero snapshot read failures. Thus the
published total came from restart restoration, not new input in this run.

The controller requested normal Quit at 15 seconds and exited 0 before the
20-second forced-stop deadline. The quit action records stopped, no live
session, no unsaved reduction/scheduler data and `quitDecision=terminate`.
The summary also reports `captureSessionLive=false`. An outside-sandbox process
check found no KeyRecordApp remaining. Forced stop was not exercised.

Together, the coordinated input and readback rounds establish bounded physical
input, reported durable save and aggregate retention across normal quit/restart
for this signed Debug candidate. They do not independently establish the
application/shortcut identity rows, crash recovery, closed-interval privacy,
complete Keychain lifecycle or Release qualification.

## Permission round stopped on a system prompt

The next permission round was separately prepared and launched only after the
owner explicitly confirmed readiness. The local controller's `--permission`
mode passed Swift 6 compilation and its no-launch check, preserves prior files,
and requests normal Quit at 115 seconds with a 120-second stop deadline. The
read-only `PrivacyTrialReport` adapter compiles against the repository's existing
`ResourceEvaluation.swift` and calls `PrivacyIntervalEvaluator.evaluateClosed`;
it neither starts capture nor reads keys or encrypted store content. Running it
on the preceding readback journal correctly reported missing-boundary, not PASS.

Candidate, installation, root and namespace were unchanged. The controller log
is `/private/tmp/keyrecord-mvp-permission-controller-20260929.log`; the root now
also contains `privacy-permission.jsonl` and `summary-permission.json`. After
Collecting was observed, the owner was instructed to turn off this trial's
Input Monitoring and reported a restart or authentication prompt. This was the
agreed stop condition. A normal-termination request matched both the exact
installed path and bundle ID, the controller exited 0 before its deadline, and
an outside-sandbox process check found no remaining KeyRecordApp. No prompt was
confirmed by the agent, and no regrant, new test input or relaunch was performed.
The final Settings toggle state remains unverified and was not changed back.

The journal has 66 records: five collecting records, then 61 blocked records.
The seq 6 transition has `privacyTrigger=sourceStopped`,
`blockedReason=sessionLocked`, `captureSessionLive=false` and
`sensitiveContentVisible=false`; seq 7 begins `protectedStateClosed`. All four
recorded Input Monitoring witnesses before closure were granted. There was no
denied witness or tap-disabled event. Thus source closure was observed, but its
causal relationship to the permission change versus the system prompt is not
isolated. No actual screen-lock result is claimed from the blocked reason.

Across the 60 records from closure through normal Quit, gate entries remain 68,
snapshot attempts/publications 13 and analysis attempts/publications 14; input,
handoff, normalization and durable-write counters remain zero. The aggregate
summary retains shortcuts 3 and bare keys 0, with no input or writes in this
run. The existing evaluator returns `inconclusive / interval-not-ended` because
there was no recovery end boundary. This is partial fail-closed observation,
not same-process revoke/regrant, exhaustive read protection or continuous
privacy qualification. See [permission trial details](PERMISSION_RECOVERY_TEST.md).

## Generic privacy reason repair

The owner clarified the prior prompt requested Quit and Reopen. Code inspection
then located `handlePrivacyInvalidation()` assigning `sessionLocked` regardless
of its caller. The existing permission-poll, disabled-tap and stopped-source
hostless tests gained assertions requiring a generic privacy-check reason on
their unlocked fake host. All three failed before the behavioral repair with
actual `sessionLocked` versus expected `privacyCheckRequired`.

The common handler now defaults to `privacyCheckRequired`; the explicit-start
lock rejection passes `sessionLocked` explicitly, and the dedicated lock
closure path is unchanged. No capture, store/key protection, manual-recovery
fence or trial-isolation restriction was weakened. The full 53 recovery/quit
tests and 233 Core tests passed after the change. Debug build-for-testing passed.
Logs are `/private/tmp/keyrecord-permission-repair-red.log`,
`/private/tmp/keyrecord-permission-repair-green.log`, and
`/private/tmp/keyrecord-permission-repair-core.log`. This verifies classification
and preserved synthetic recovery behavior, not a newly observed host recovery.

The local controller's next `--recovery` mode preserves all five earlier rounds
and writes `privacy-recovery.jsonl` / `summary-recovery.json`, with normal Quit
at 55 seconds and forced stop at 60. It requires a separately coordinated ready
response before launch. Re-enabling the trial's permission while it is stopped
and launching through the isolation controller will test the system-required
restart path; it cannot qualify same-process regrant. Prior live results stay
bound to the old signed source rather than being transferred to the repair.

## Regrant/restart follow-up and foreground rebuild repair

Signed `10676e1aa` replaced the installed trial at the same path, identity and
namespace, retaining the earlier App under a private backup path. Its first
approved restart failed before capture with denied Input Monitoring. Exact
trial TCC evidence and read-only Settings inspection agreed the trial was off;
a distinct KeyRecordApp row was on. The trial exited normally with zero sessions
or writes. The agent did not change system permissions.

After the owner enabled the exact trial and confirmed readiness, the separate
`--recovery2` run reached Collecting and received the confirmed one Command-A.
It recorded aggregate delta 1, shortcut total 4, bare total 0, one successful
durable write, no write/read failures, and two capture sessions. The controller
requested normal Quit at 55 seconds and exited 0 before 60 seconds; process
inspection found no remaining App. Evidence: the existing private root's
`privacy-recovery2.jsonl`, `summary-recovery2.json`, and
`/private/tmp/keyrecord-mvp-recovery2-controller-20260929.log`.

The journal also records a `sourceStopped` / `privacyCheckRequired` block before
Quit. Restored permission and input/save after isolated restart are observed;
stable recovery is not yet qualified. A hostless test then held a foreground
rebuild across multiple monitor polls and reproduced the same false block
before the fix. The monitor now recognizes health reads overlapping runtime
reconciliation using its outstanding calls and the existing queue generation.
Permission, lock and Secure Input checks continue. The additional protection
test revokes permission during a held rebuild and requires closure to persist.
No further live launch was performed for this diagnosis or repair.
Debug build-for-testing and all 55 recovery/quit tests passed after the repair,
with zero failures. Red/green logs are
`/private/tmp/keyrecord-rebuild-race-{build-red,red,build-green,green}.log`.
These are synthetic results for the newer repair, not another host qualification.

## Bounded host confirmation of `8e3ca0c55`

The signed repair built using existing assets and was installed at the same
trial path, retaining `10676e1aa` at
`/private/tmp/keyrecord-mvp-installed-10676e1aa-backup.app`. Strict signature and
no-launch isolation checks passed. The locally compiled controller's new
`--recovery3` mode preserves all earlier evidence and uses new journal/summary
files. Only after explicit owner readiness did this one 60-second round launch.

The owner confirmed one Command-A and returned from TextEdit to chat. Three
capture sessions occurred. All 15 pre-stop journal records stayed Collecting;
two final records were Stopped, with no Blocked phase or privacy trigger.
Summary totals: 3 down/3 up/6 modifier callbacks, 12 accepted handoffs, delta 3,
shortcuts 7/bare keys 0, 4 issued and 4 successful durable writes, zero failures,
timeouts, invalidations, overflow or snapshot read failures. Aggregate evidence
does not identify the other two shortcut increments or exact attribution.

The controller requested normal Quit at 55 seconds and exited 0 before 60
seconds. The quit action records stopped, sessionLiveAfter=false, saved and
terminate. A process check found no remaining App; forced stop was not used.
The summary's cached live flag is not a teardown witness. Evidence lives in the
same private root as `privacy-recovery3.jsonl` / `summary-recovery3.json` and in
`/private/tmp/keyrecord-mvp-recovery3-controller-20260929.log`.

The narrow permission regrant/isolated-restart and false foreground-rebuild
block task is complete for this candidate. The owner needs no further action
for this round; this does not expand the acceptance scope to the items below.

## Bounded lock round and diagnostic interval repair

One separately approved/readied lock round on signed `8e3ca0c55` observed capture
closed and hidden state across 52 locked and 42 unlocked-before-Start samples.
All sampled gate/input/read/publication/write counters were unchanged from the
closed begin at seq 13 to explicit Start at seq 109. Start verified unlocked and
granted conditions, restored Collecting, and the owner confirmed new input.
Normal Quit at 175 seconds completed within the 180-second bound; no process
remained. The final totals are 9 shortcuts and 2 bare keys, with 9 successful
durable writes and no write/read failure. The two bare increments occurred
before closure and are not independently attributed.

The unmodified evaluator nevertheless reports 20 gate admissions in its span:
its old `captureSessionStarting` endpoint occurs after the manual action has
reopened the store. A hostless test reproduced this boundary mismatch. The Debug
journal now ends immediately before the already-authorized store reopening and
labels it `protectedStoreReauthorized`; actual protection behavior is unchanged.
All 55 recovery/quit and 15 interval evaluation tests pass after red reproduction.
The new recording repair has separate bounded observations on `cf08a07c`; the
second sleep round above also verifies post-wake input/save. Original lock journal,
summary and flagged evaluation are retained. See [the detailed record](PERMISSION_RECOVERY_TEST.md#bounded-collecting-lock-and-explicit-recovery--2026-09-29).

Still open: current-candidate attribution rows, native consent
and accessibility, permission revoke/regrant, continuous lock/sleep closure and
recovery, exhaustive live product observation for the hosted Keychain controller,
and qualified Release composition. The two current-protocol native ARM resource
windows are complete for the signed `a604ad535` fixed-replay candidate, as recorded
at the top of this document. Release
still uses `BlockedLiveKeychain` and `UnqualifiedCapture`. The final signed
collecting Release must receive its own FR-P1 source/binary audit. These gaps are
not converted to PASS by the tests or the unsigned build above.
