# Second bounded sleep recovery round

Prepared at the owner's request after the first round ended before final input.
No second launch has occurred. Wait for explicit readiness after communicating
the full sequence and the revised five-minute limit.

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
