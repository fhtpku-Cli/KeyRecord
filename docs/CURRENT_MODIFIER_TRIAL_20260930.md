# Bounded modifier reconstruction trial

Status: installed and run once after explicit owner approval/readiness. Normal
exit completed. Modifier acceptance did not pass: the two aggregate increments
were published as bare keys, not shortcuts. Visible details were not inspected
before the deadline. Preserve this consumed run; no automatic repeat is authorized.

## Completed round and unexpected classification

The owner approved installation and validation after confirming readiness. The
old installed bundle was moved to
`/private/tmp/keyrecord-mvp-before-modifier-426969c9f.app`, then the staged bundle
was installed at `~/Applications/KeyRecord MVP Trial 20260929.app`. Recursive
`diff -qr` of the entire staged and installed bundles returned zero. Both staged
and installed no-launch controller checks passed. Performance Trial was untouched.

The retained controller launched exact PID `34309` using the new root/namespace
below. The owner chose Start/consent and reported started; the journal confirmed
Collecting with actual capture queue and key gate open. The owner then reported
completion of Command-alone release, two left Command+A presses and mouse Pause.
Sequence 63 confirms Paused with capture queue closed. The subsequent request to
inspect expanded modifier details was not completed: the owner reported that the
App had exited. The controller requested normal Quit at its 175-second bound and
returned `exited=true quitRequested=true failed=false`, exit code 0. A read-only
`ps -p 34309` check found no remaining process. No relaunch occurred.

Final `modifier-summary.json` reports:

| Observation | Result |
| --- | --- |
| Aggregate delta | 2 |
| Last published shortcut / bare-key total | **0 / 2** |
| Tap key-down / key-up / flags-changed callbacks | 2 / 2 / 2 |
| Accepted / closed / overflow handoffs | 6 / 0 / 0 |
| Normalization outputs | 4 |
| Preparation attempts | 4 |
| Issued / returned / successful / durable writes | 5 / 5 / 5 / 5 |
| Failed / timed-out / invalidated writes | 0 / 0 / 0 |
| Snapshot read failures / tap-disabled events | 0 / 0 |
| Final capture queue / live session | closed / false |

The earlier conversational statement calling aggregate delta 2 "two shortcuts"
was corrected after reading the category totals. These are last-published model
totals plus reported durable writes, not a fresh encrypted-store readback or
rendered-row proof. Stop retains those last-published diagnostic values while
hiding sensitive presentation. The input protocol expected six flags callbacks
and ten handoffs; this run observed only two and six, respectively. Neither the
missing callbacks nor the input flags can be reconstructed from these totals.

Preparation markers at sequences 31, 37 and 57 have accepted=0/aggregate=0;
sequence 60 has accepted=6/aggregate=2, equal to final values. No preparation mark
is recorded at an intermediate accepted count. The markers place the recorded
input between preparations three and four; they do not support blaming a repeated
preparation between the two counts. Counters explicitly are non-atomic snapshots,
and contain no event flag values, exact key identities or physical-event order.

Read-only source review found no swapped category fields from reducer through
presentation to diagnostic serialization. The relevant implementation matches
the installed candidate. Each key-down independently decodes its Command flag;
an active Command family remains a shortcut even when side is unknown or a
flagsChanged callback is missing. Therefore reset or missing flagsChanged alone
does not explain a Command-active key-down becoming bare. The live incoming flag
values remain unknown; no speculative reconstruction change was made. The next
distinguishing observation would be aggregate category counts at the native decode
and reduction boundaries, without raw keys or event traces. That diagnostic work
and any separately approved live round are still pending.

Offline verification after the round: `swift test --filter CaptureQueueTests`
passes all 16 cases, including Command-active key-down after revoke/reopen without
a preceding flagsChanged event. `ModifierRecoveryTests` passes its one case for
unknown-first-press then observed-release/left recovery. The first combined filter
used a file name (`CaptureDeliveryTests`) rather than its actual extension class
(`CaptureQueueTests`), so it ran only the recovery case; the corrected class run
above supplies the remaining 16 results. These synthetic checks cannot establish
the missing native flag values from this live run.

This round confirms bounded startup, two counted inputs, reported durable saves,
Pause closure and normal exit. It does not qualify Command+A classification,
left-side provenance, rendered details, restart retention or collecting Release.

## Candidate

- Source: `426969c9f`, clean isolated `codex/phase1-acceptance` checkout at build.
- Signed native arm64 Debug bundle:
  `/private/tmp/keyrecord-phase1-modifier-candidate-20260930/build/Build/Products/Debug/KeyRecordApp.app`.
- Bundle identity: `com.keyrecord.trial.mvp20260929`, team `P3W62C39TN`.
- Build used existing local signing materials without provisioning updates.
- Build log: `/private/tmp/keyrecord-phase1-modifier-candidate-20260930/build.log`.
- Before approved installation, preserve the current installed `346dc26d8` bundle
  at the unused path `/private/tmp/keyrecord-mvp-before-modifier-426969c9f.app`.
  Install only to `~/Applications/KeyRecord MVP Trial 20260929.app`; leave the
  Performance Trial untouched. Compare installed and staged bundles recursively
  after copy, including `KeyRecordApp.debug.dylib`; this Debug build's main
  executable is only the launcher, not all compiled product code.

The candidate includes the session-preparation observation, category-specific
empty messages and preceding deletion safety repairs. The existing launcher
signature/profile/application-identifier checks pass. The English bare-key empty
message is present in the built catalog. This is a development diagnostic
candidate, not qualification of the collecting Release composition.
The arm64 `KeyRecordApp.debug.dylib` contains the new `captureSessionPrepared`
marker; inspecting the small Debug launcher alone does not inspect that code.

## Isolation and bound

Private root: `/private/tmp/keyrecord-phase1-modifier-live-20260930`, created
with mode 0700 and empty at the prelaunch checks; now occupied and preserved. Used Keychain namespace:
`com.keyrecord.trial.mvp20260929.phase1modifier20260930`. Preparing the directory
does not prove that the Keychain namespace is empty; no Keychain data operation
was performed during preparation.

Controller source: `/private/tmp/keyrecord-phase1-modifier-controller-20260930.swift`.
Executable: the same path without `.swift`, built with `swiftc -parse-as-library`.
`--check <absolute-app-path>` returned
`ready=true launched=false normalQuitSeconds=175 stopSeconds=180` against the staged
candidate and installed bundle. `--run` was used once for the approved installed bundle. It checks the
private root's ownership/mode/symlinks, exact bundle ID, absence of a same-ID running
process, empty root and the existing signing preflight before launch. It retains
the previous controller's exact-instance identity and launch-date checks.

The controller requests normal Quit at 175 seconds; at 180 seconds it stops only
the identified trial instance and records unverified normal exit. An earlier
`modifier-quit.request` in the private root requests normal Quit. Outputs are
`modifier-privacy.jsonl` and `modifier-summary.json`. Preserve them; an occupied
root prevents repeating this one-use run. Stop on permission, authentication,
restart or Keychain prompts without changing permissions. No sleep, lock, network
capture or performance measurement is included.

## Owner-assisted steps

1. Explain the following sequence and wait for approval/readiness with blank
   TextEdit prepared. Only then preserve/install the bundle and launch once.
2. Ask the owner to choose Start and accept the local aggregate consent. Wait for
   the owner to report Collecting, then check actual queue/key admission and the
   latest diagnostic state before asking for input.
3. Ask the owner to switch to blank TextEdit, release all modifiers, then press
   and release **left Command alone once**. Next press left Command+A twice,
   releasing the keys between presses. Stay in TextEdit throughout that sequence.
   Finally use the mouse to choose Pause in the trial menu and report completion.
4. Confirm closed admission after Pause. If time remains, ask the owner to open
   Settings > Aggregates and expand **Exact modifier sides and key code**, reporting
   the visible side/count or supplying a screenshot of this trial window. Do not
   resume or request additional input to repair an unexpected result.
5. Request normal Quit after the report and confirm exact process exit and final
   counters. If the deadline arrives first, record partial evidence and stop.

## Interpretation

Pressing and releasing Command alone supplies an observed release within the
active capture session; merely asking the owner to release already-up keys does
not guarantee that a release event is delivered after capture begins. The existing
synthetic pipeline test demonstrates left-side preservation after such an observed
release, without changing conservative unknown-side behavior following a reset.

The intended input contains two shortcut presses, two key-up callbacks and six
modifier callbacks (Command-alone down/up plus the two chords), with no bare-key
increment. These are expected controls, not recorded results. Additional counts
or different variants must be reported, not normalized away. Command-alone should
not create an aggregate count. A new preparation marker between the release and
input can legitimately reset reconstruction; interpret cumulative handoff and
aggregate counts at the markers without treating the counters as atomic or as an
event trace. `sessionCount` records preparation attempts, not successful starts.

If two left-side uses are displayed and saved with the expected totals, this is
bounded current-candidate modifier evidence. Unknown results remain unresolved
unless the available preparation/count observations distinguish their cause.
This round does not retroactively fix the old unknown-side records or establish
native accessibility, an independent OS lock witness, exhaustive hosted lifecycle
observation or collecting Release qualification.
