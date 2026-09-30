# Bounded permission closure and restarted recovery

## Scope and execution

The owner approved installation and two separately readied segments on signed
arm64 Debug source `fde8c8886`, then confirmed readiness for each segment.
The installed `KeyRecord MVP Trial 20260929.app` matched staging in full; the old
bundle is retained at `/private/tmp/keyrecord-mvp-before-permission-fde8c8886.app`.
Bundle, team, private root and namespace are those in
[the prepared procedure](PERMISSION_TRIAL_PREPARATION_20260930.md).
Performance Trial and daily data were not used.

The permission segment launched PID 40734. An explicit Resume action moved Paused
to Collecting with permission granted. The owner then disabled only MVP Trial's
Input Monitoring and reported the macOS Quit and Reopen prompt without accepting
it. Product closure was observed and the controller requested early normal Quit.
It exited zero; `ps` confirmed that exact PID was gone.

After the owner restored permission with the App closed and separately confirmed
readiness, the recovery segment launched PID 41754. Granted permission and actual
Collecting/queue admission were observed. Following explicit instructions, the
owner reported one left Command+A in blank TextEdit and Pause. The controller
requested early normal Quit, exited zero, and the exact PID was gone.

## Observed results

| Observation | Permission segment | Recovery segment |
| --- | --- | --- |
| Accepted handoffs / aggregate delta | 0 / 0 | 4 / 1 |
| Key-down / key-up / modifier callbacks | 0 / 0 / 0 | 1 / 1 / 2 |
| Last published shortcuts / bare keys | 2 / 0 | 3 / 0 |
| Issued / returned / successful / durable writes | 1 / 1 / 1 / 1 | 3 / 3 / 3 / 3 |
| Write failures / timeouts / invalidations / snapshot read failures | all zero | all zero |
| Exit | normal, no unsaved work | normal, no unsaved work |

The permission segment recorded 32 blocked observations (seq 20 through 82,
even-numbered). Queue and key gate were closed, sensitive content hidden, and
sampled handoff, aggregate and protected-read/processing counters unchanged.
The recorded privacy trigger was `tapUnavailable`, with reason
`privacyCheckRequired`. All 40 permission witnesses still reported granted;
there was no denied or unknown witness. The new tri-state recorder did not turn
this host behavior into an explicit-denial observation.

Recovery's first records are Unstarted session preparation followed by Collecting,
with expectedCollecting true. It has no Start, Resume or Accept action record;
the only traced action is Quit. Although the owner confirmed seeing Collecting,
this supports startup restoration, not an observed manual recovery action.
The current startup code deliberately resumes a persisted collecting preference.
The log alone does not establish why macOS continued reporting granted after the
owner toggled its setting.

Pause closed recovery's actual queue at seq 19 after delta one and three durable
writes. Quit recorded Stopped and no live session. Its key gate remained open;
normal Pause/Quit is not described as a key revocation. Final published totals
were three shortcuts and zero bare keys; this is not an additional post-exit
readback or current rendered-row inspection.

## Evidence and limits

Artifacts are `permission-summary.json`, `permission-privacy.jsonl`,
`recovery-summary.json`, `recovery-privacy.jsonl`, and the two early quit requests
under `/private/tmp/keyrecord-phase1-chords-live-20260930`. Controller logs:
`/private/tmp/keyrecord-phase1-permission-live-controller.log` and
`/private/tmp/keyrecord-phase1-permission-recovery-controller.log`.
Both stage names are consumed; no automatic repeat or extra launch is authorized.

This round proves bounded product closure after the reported setting change,
preservation of the two existing shortcuts through restart, and acceptance/save
of one subsequent chord. Explicit denied permission, manual recovery on this
restart, same-process regrant, continuous privacy, full hosted Keychain observation
and collecting Release remain unqualified. No existing evidence is relabeled PASS.

Both CI jobs on preparation/documentation head `80061ab1f` completed successfully:
[PR run](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36687721340) and
[push run](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36687714536).
They do not establish live host qualification.
