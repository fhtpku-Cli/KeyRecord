# Bounded modifier reconstruction trial

Status: prepared, not installed or run. Fresh owner approval and readiness are
required before replacing or launching the installed trial.

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

Fresh private root: `/private/tmp/keyrecord-phase1-modifier-live-20260930`, created
with mode 0700 and still empty after the no-launch check. Planned Keychain namespace:
`com.keyrecord.trial.mvp20260929.phase1modifier20260930`. Preparing the directory
does not prove that the Keychain namespace is empty; no Keychain data operation
was performed during preparation.

Controller source: `/private/tmp/keyrecord-phase1-modifier-controller-20260930.swift`.
Executable: the same path without `.swift`, built with `swiftc -parse-as-library`.
`--check <absolute-app-path>` returned
`ready=true launched=false normalQuitSeconds=175 stopSeconds=180` against the staged
candidate. `--run` is reserved for the approved installed bundle. It checks the
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
