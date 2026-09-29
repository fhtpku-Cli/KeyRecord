# Second bounded sleep recovery round

Completed after the owner's explicit readiness on 2026-09-29. This signed
`cf08a07c` round observed sleep closure, wake without automatic collection,
explicit Start, new post-wake input and successful save, then normal early Quit.
Its output paths are consumed; do not relaunch this mode or reuse them.

## Observed result

- The owner confirmed one initial Command-A, wake without Start, then another
  Command-A after Start/consent and Collecting. Final shortcut total is 12, up
  from retained 10; bare-key total remains 2. The aggregate delta is 2, with two
  key-down, two key-up and four modifier callbacks. Aggregate-only records do not
  independently establish the precise app/shortcut attribution row.
- The controller launched PID 34173. willSleep occurred at continuous second
  70.637, didWake at 110.436; continuous minus awake duration establishes 32.028
  seconds suspended. The four-event witness report returns observed, leaving
  productPass and continuous privacy claims false.
- Product sequence 20 begins closure with workspaceWillSleep. All 75 records
  through protectedStoreReauthorized at sequence 94 keep capture closed and
  sensitive state hidden. There are 13 locked and 57 unlocked observations.
  Gate admissions stay 249, aggregate delta 1, handoffs 4, normalization 2,
  durable writes 2, snapshot attempts/publications 65 and analysis attempts/
  publications 68. The evaluator reports observed for this single closed span
  with zero counter deltas; these remain finite, non-atomic observations.
- Explicit Start begins at 93 and ends at 96: fresh unlocked/secure-disabled
  readiness, granted permission and Collecting/live capture. Consent accept is
  recorded at 100-101. Sequence 103 subsequently records aggregate delta 2,
  handoffs 8, normalization 4 and five durable writes, demonstrating new input
  and successful save after recovery. Later post-reauthorization activity is
  outside the closed span and is not claimed to be zero.
- All 12 issued writes returned successfully and durably, with zero failures,
  timeouts, invalidations, overflow, snapshot failures or journal write failures.
  Fourteen capture sessions occurred during foreground changes; no new Blocked
  phase followed the explicit recovery.
- After observing saved post-recovery input, QuitTrial requested normal Quit.
  Quit actions 112-114 report Stopped, sessionLiveAfter=false, saved and terminate.
  The controller exited 0 at continuous second 223.431, before the 295/300 limits.
  Both exact-instance and outside-sandbox process checks found no App remaining.
  The summary's cached captureSessionLive=true is not an exit witness.

Evidence is retained in the three second-round output files below and
`/private/tmp/keyrecord-mvp-sleep2-controller-20260929.log`. The unchanged
PrivacyTrialReport and SleepWitnessReport.py read only these coarse records;
no encrypted records or keys were inspected.

This completes the narrow current-candidate collecting sleep/wake/manual Start/
new-input/save/normal-exit scenario. It does not establish continuous privacy,
every protected read, rendered pixels, paused sleep, complete hosted Keychain
lifecycle or Release qualification. The earlier partial round remains unchanged.

## Original preparation

Use the unchanged installed signed `cf08a07c` App, bundle/Keychain namespace
`com.keyrecord.trial.mvp20260929` and private root
`/private/tmp/keyrecord-mvp-readiness-20260929`. Retained totals are 10 shortcuts
and 2 bare keys. All first-round files remain untouched. The new outputs are
`privacy-sleep2.jsonl`, `summary-sleep2.json` and `sleep-witness2.jsonl`.

The local BoundedTrial controller supports `--sleep2-check` and `--sleep2`.
Normal Quit is requested at continuous second 295, forced stop at 300; the clock
includes sleep. If the machine is asleep at the deadline it cannot execute code;
upon a late wake the controller stops immediately when scheduled. No automatic
extension or repeat is authorized. The original round retains its 175/180 limits.

## Sequence communicated before launch

1. After readiness, launch once and confirm Collecting with granted permission.
   Ask for one Command-A in blank TextEdit and wait for its saved aggregate.
2. Tell the owner to choose Apple menu > Sleep, wait about 30 seconds, then wake
   and unlock. The owner replies once back; do not ask for input while asleep.
3. Keep Start untouched for at least five seconds after fresh unlocked evidence.
   Verify closed capture, hidden state and unchanged observed counters.
4. Ask the owner to select Start (and accept the trial consent if presented),
   wait for Collecting, then press one Command-A in blank TextEdit and reply.
   If permissions, Keychain errors or an unexpected restart prompt appear, stop
   normally without changing settings.
5. Verify a new post-recovery callback/aggregate and successful durable save.
   Request normal Quit early, then verify the exit action, summary and no exact
   trial process. The deadline is a fallback, not a target wait.

The local QuitTrial helper matches both the exact installed path and namespace;
it requests normal termination only and never launches an application. If there
is insufficient time for a step, stop and preserve a partial result. Ask before
any further live attempt. Do not access the daily store, change permissions,
inspect encrypted records or run packet capture.

## Preparation and interpretation

Swift 6 compilation and 14 synthetic controller checks passed, including both
rounds' output names and 295/300 deadline edges. The installed `--sleep2-check`
passed without launch. SourceKit's standalone @main complaint does not use the
actual compiler's `-parse-as-library`; the real compile passed.

Use the unchanged PrivacyTrialReport and SleepWitnessReport.py read-only tools.
Require actual sleep timing, product sleep closure, stable counters until
protectedStoreReauthorized, fresh explicit Start readiness and post-recovery
input/save. Report observations separately from continuous privacy, every-read,
rendering, full Keychain lifecycle and Release claims, which remain unproven.
The first round's partial result is preserved in
[its own record](SLEEP_WAKE_ROUND_20260929.md).
