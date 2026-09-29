# Prepared sleep, wake and explicit recovery round

Preparation only. No real sleep round has run. Obtain the owner's explicit
readiness before launch; pause here while the owner is unavailable.

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
  No App process or new sleep output existed afterward. Awaiting owner readiness;
  no new live result is implied by these checks.
