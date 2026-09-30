# Bounded modifier reconstruction trial

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round. The later [explicit chord trial](CURRENT_COMMAND_CHORD_TRIAL_20260930.md) verified two left Command+A shortcuts. This earlier standalone-A result remains distinct.

Status: installed and run once after explicit owner approval/readiness. Normal
exit completed. After the round, the owner clarified that the instruction was
understood as Command press/release followed by two standalone A presses. Published
bare-key total 2 / shortcut total 0 is consistent with that operation. Command+A
and modifier-side acceptance remain untested, not a demonstrated classification
defect. Preserve this consumed run; no automatic repeat is authorized.

## Completed round and corrected interpretation

The owner approved installation and validation after confirming readiness. The
old installed bundle was moved to
`/private/tmp/keyrecord-mvp-before-modifier-426969c9f.app`, then the staged bundle
was installed at `~/Applications/KeyRecord MVP Trial 20260929.app`. Recursive
`diff -qr` of the entire staged and installed bundles returned zero. Both staged
and installed no-launch controller checks passed. Performance Trial was untouched.

The retained controller launched exact PID `34309` using the new root/namespace
below. The owner chose Start/consent and reported started; the journal confirmed
Collecting with actual capture queue and key gate open. The owner then reported
completion and mouse Pause. The initial report was interpreted as the intended
Command-alone release followed by two left Command+A chords. The owner's later
clarification establishes that the instructions were understood as a Command
press/release followed by two standalone A presses; the chord sequence was not
established by the earlier completion reply.
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
hiding sensitive presentation. The originally intended chord protocol would
produce six flags callbacks and ten handoffs. The clarified Command press/release
plus two standalone A presses instead predicts two flags callbacks, two key-downs,
two key-ups, six handoffs and two bare-key increments, matching the observed totals.
The initial description of missing callbacks and a classification mismatch is
withdrawn. Cumulative counters still do not prove exact key identities or order.

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
values remain unknown, but the clarified procedure supplies an explanation
consistent with the result. No speculative reconstruction change was made.
Additional category-boundary instrumentation is not justified by this round.
The next modifier check should use the unchanged candidate and explicit
"hold Command while pressing A, then release both" instructions, with fresh
approval/readiness and a new isolated run. It has not been launched.

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
   and release **left Command alone once**. Next **hold left Command down, press A
   while still holding Command, then release both keys**. Repeat that complete
   hold-Command/press-A/release-both sequence once. Stay in TextEdit throughout.
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
