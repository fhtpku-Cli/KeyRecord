# Sleep, wake and explicit recovery round

This round ran after explicit owner readiness on 2026-09-29. Its output paths
are consumed. The original preparation below is retained as history; do not
relaunch it. Closure and explicit Start recovery were observed, but the deadline
expired before the owner could perform the post-recovery input step.
The separately approved [second round](SLEEP_WAKE_SECOND_ROUND_20260929.md)
completed that bounded scenario on the same candidate. This first result and
its original evidence remain unchanged.

## Observed result on signed cf08a07c

The controller launched PID 32228 and exited 0 at continuous second 175.298 after
normal Quit. An outside-sandbox process check found no remaining KeyRecordApp.
The owner confirmed the initial Command-A, sleep/wake and no Start before the
recovery instruction. After the deadline the owner reported there was not enough
time for the final input. Multiple chat handoffs consumed the bounded window;
missing post-recovery input is not an established product event-delivery failure.

- System witnesses: willSleep at 66.544 seconds, didWake at 121.793; the continuous
  versus awake clock difference establishes 29.793 seconds suspended. The ordered
  four-event witness report returns observed, with productPass and continuous
  privacy claims false.
- Product sequence 18 begins closure with workspaceWillSleep. All 74 records
  through sequence 91 keep capture closed and sensitive state hidden. They include
  31 locked and 38 unlocked observations; unlocked begins at sequence 52. Gate
  admissions remain 234, aggregate delta 1, handoffs 4, normalization 2, durable
  writes 3, snapshot attempts/publications 59 and analysis attempts/publications
  62. These are finite non-atomic observations, not continuous proof.
- Explicit Start begins at sequence 90. The repaired protectedStoreReauthorized
  endpoint at 91 retains those same counters, before authorized recovery reads.
  Start ends at 93 with granted permission, fresh unlocked/secure-disabled
  readiness and Collecting/live capture. An accept action is also recorded at
  97-98; it does not establish additional physical input.
- The unchanged interval evaluator reports observed for one closed interval,
  with zero deltas from 18 to 91. It also reports later activity from 91 to 101;
  those post-reauthorization deltas are outside the closed interval, not claimed
  to be zero. The earlier lock journal and its flagged result remain untouched.
- Final totals: shortcuts 10 (previously 9), bare keys 2 (unchanged), aggregate
  delta 1; one key-down, one key-up and two modifier callbacks. All four issued
  writes succeeded durably; write failures/timeouts/invalidations, overflow,
  snapshot failures and journal write failures are zero. No new callback or
  aggregate appears after explicit recovery, so post-wake input/save remains open.
- Quit action 99-101 reports Stopped, sessionLiveAfter=false, saved and terminate.
  The summary's cached captureSessionLive=true is not an exit witness.

Evidence: the three sleep output files below and
`/private/tmp/keyrecord-mvp-sleep-controller-20260929.log`. The read-only reports
were run against these files; no encrypted database or keys were inspected.

Next live preparation must reserve enough time for owner actions and reduce chat
handoffs. Confirm the full sequence before launch, preserve a finite deadline,
and obtain fresh scope/readiness. Do not silently extend or repeat this round.
This result validates the new journal boundary on a real sleep cycle but does
not complete post-wake input durability, full Keychain lifecycle or Release.

## Candidate and scope

- Product source: `cf08a07c`, containing the diagnostic repair `1e3918136`.
  The new commit adds only a hostless sleep recovery test.
- Target: `~/Applications/KeyRecord MVP Trial 20260929.app`.
- Bundle and Keychain namespace: `com.keyrecord.trial.mvp20260929`.
- Existing private root: `/private/tmp/keyrecord-mvp-readiness-20260929`.
  Use only its isolated encrypted store. Last reported totals: shortcuts 9,
  bare keys 2. Do not inspect or decrypt the database externally.
- New output paths: `privacy-sleep.jsonl`, `summary-sleep.json` and
  `sleep-witness.jsonl`. Existing records remain intact; a partial run consumes
  these paths and cannot be silently repeated.
- Normal Quit at 175 seconds, forced stop of this exact trial instance at 180.
  The deadline uses [ContinuousClock](https://developer.apple.com/documentation/swift/continuousclock),
  which includes sleep; the separate [SuspendingClock](https://developer.apple.com/documentation/swift/suspendingclock)
  witness excludes it. Code cannot execute while the machine sleeps. If it wakes
  after the limit, stop immediately when scheduled; do not continue the trial.
- Only the owner sleeps and wakes the machine. No permission changes, separate
  lock test, account configuration, packet capture or ordinary statistics access.

## Owner sequence after explicit readiness

1. Launch through the prepared controller's `--sleep` mode. Confirm Collecting
   and granted Input Monitoring before asking for physical input.
2. Ask the owner for one Command-A in blank TextEdit, then wait for a successful
   save. Aggregate counts cannot prove exact attribution of all increments.
3. Ask the owner to use Apple menu > Sleep, wait about 30 seconds, then wake
   and unlock normally. Do not request credentials or input while asleep.
4. After wake, wait at least five seconds without Start. Confirm fresh unlocked
   availability while capture remains blocked, the store gate closed and
   sensitive UI hidden. Unexpected automatic collection or permission/Keychain
   prompts require normal Quit, without changing settings.
5. Ask the owner to select Start in the trial menu. Confirm explicit action,
   fresh readiness and Collecting, then request one Command-A in blank TextEdit.
6. Quit early after enough evidence, otherwise let the controller end the round.
   Verify normal exit, summary and absence of the exact trial process.

Allow the round to end if an owner step is late. Never extend or relaunch it to
obtain a pass. A forced stop or absent summary cannot establish durable recovery.

## Evidence interpretation

The local controller records only event names and elapsed clock values. Require
the ordered controllerStarted/willSleep/didWake/processExited witnesses and a
positive suspended-time difference. A notification pair with zero suspended
time, screen lock alone, or missing notifications is not a verified sleep cycle.
Also require the product's sleep invalidation evidence; the controller's witness
does not establish product closure by itself.

Evaluate the product's closed interval through `protectedStoreReauthorized`,
which ends it after fresh unlocked verification and immediately before explicit
store reauthorization. Separately verify the subsequent successful Start and
new durable input. The older lock journal retains its original marker and
flagged result; this preparation does not rewrite it as a pass.

Read only the coarse journal/summary with the recompiled local
`PrivacyTrialReport`, and `sleep-witness.jsonl` with `SleepWitnessReport.py`, both
under `/private/tmp/keyrecord-mvp-profile-attempt-20260929`. The latter reports
sleep timing only and always leaves productPass/provesContinuousPrivacy false.
Finite observations do not prove continuous protection, every protected read,
rendered pixels or the full hosted Keychain lifecycle. Release remains blocked
by its existing composition and unqualified capture boundary.

## Preparation evidence

- On `1e3918136`: all 55 recovery/quit and 15 interval evaluator tests passed;
  both PR CI jobs subsequently passed (6m29s and 6m18s).
- On `cf08a07c`: Debug test build and the new focused
  `testSleepInvalidationRequiresExplicitStartAfterAvailabilityReturns` passed.
  This uses fake host availability, not actual system sleep. The first build's
  missing `try` was corrected before the successful retry.
- Swift 6 controller compilation passed; its seven synthetic deadline/encoding
  checks passed without launch. The read-only witness reporter's nine synthetic
  checks passed; the privacy reporter compiled against the repaired evaluator.
- Signed arm64 Debug build passed using existing local signing assets, with no
  provisioning update. Artifact:
  `/private/tmp/keyrecord-sleep-ready-20260929/build/Build/Products/Debug/KeyRecordApp.app`.
- Installed at the target above after confirming no App process. The prior
  `8e3ca0c55` bundle is retained at
  `/private/tmp/keyrecord-mvp-installed-8e3ca0c55-backup.app`.
- Strict code-signature verification and `BoundedTrial --sleep-check` passed.
  No App process or new sleep output existed at preparation time. The separately
  approved live result is recorded above.
