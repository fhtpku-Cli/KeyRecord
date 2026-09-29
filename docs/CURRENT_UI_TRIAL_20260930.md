# Current-candidate UI and attribution check

Status: owner-approved round completed with partial evidence on 2026-09-30.
Current-candidate input, durable-save counters, paused admission and normal exit
were observed. Native row, attribution, rendering and accessibility inspection
remain unverified because the Computer Use connection failed. The preparation
and intended procedure below are retained; this is not a full UI PASS.

## Observed result

The owner explicitly approved this round and confirmed readiness. The prior
installed trial was preserved at `/private/tmp/keyrecord-mvp-before-ui-346dc26d8.app`,
then candidate `346dc26d8` was installed at the planned path and passed the same
no-launch check. The controller launched the exact trial as PID `90634`.
The owner confirmed Start/consent and Collecting. Journal action 32 independently
records granted permission, unlocked readiness, disabled Secure Input, attributable
foreground and actual open queue/key gate. These coarse inputs do not identify
the foreground application in the diagnostic output.

After the separate input instruction, the owner confirmed two left Command-A
presses and Pause. The final summary records two key-downs, two key-ups, four
modifier callbacks, eight accepted handoffs, aggregate delta two, published
shortcut total two and bare-key total zero. All six issued writes returned
successfully and were recorded durable, with zero failed/timed-out/invalidated
writes and zero snapshot-read failures. Before Quit the journal records Paused,
no live capture and the actual queue closed. The key gate remains open while
paused, permitting the intended protected display; this is not a lock-closure test.

The first native UI connection through `cua.getApp` failed with
`Sky Computer Use native pipe closed before response`. No accessibility tree or
rendered trial window was returned. As specified below, a private quit request
ended the round instead of retrying or extending capture. The controller reported
normal Quit requested, exited with `failed=false`, and returned zero. The final
Quit action reported Stopped, no live capture, closed queue and no pending reducer
or scheduler changes. A process check confirmed PID `90634` was gone. The key gate
field is a pre-exit sample; process termination, not that field, establishes that
the trial is no longer running.

The current candidate therefore has bounded physical-input/save/pause/quit
evidence. It does not yet have directly observed Command-A rows, TextEdit
attribution, exact modifier provenance, native rendering or accessibility. The
owner's report is retained separately from those missing observations. No second
launch, lock/sleep, permission toggle, performance measurement or daily-store
access was performed. Another round requires separate readiness; preserve the
occupied root and its original artifacts.

## Candidate and isolation

- Source: `346dc26d8` on `codex/phase1-acceptance`.
- Native arm64 signed Debug App:
  `/private/tmp/keyrecord-phase1-ui-candidate-20260930/build/Build/Products/Debug/KeyRecordApp.app`.
- Bundle: `com.keyrecord.trial.mvp20260929`; team: `P3W62C39TN`.
- Proposed install: `~/Applications/KeyRecord MVP Trial 20260929.app`, after
  preserving the existing trial bundle. The Performance Trial is unrelated.
- New empty private root: `/private/tmp/keyrecord-phase1-ui-live-20260930`.
- New exact Keychain namespace: `com.keyrecord.trial.mvp20260929.phase1ui20260930`.
- Build used existing local signing assets with no provisioning update. The
  signature/profile/required-isolation check passed without launch.

The one-round controller source is
`/private/tmp/keyrecord-phase1-ui-controller-20260930.swift`, compiled with
`xcrun swiftc -parse-as-library` to the matching path without `.swift`.
It rejects an occupied root or running same-ID App, verifies the supplied bundle
through the existing trial checker, and launches only with `--run` plus the exact
App path. It requests normal Quit at 175 seconds and stops that trial instance at
180 seconds. An earlier `ui-quit.request` in the private root requests normal Quit.
Unexpected exit does not produce controller success. The timeout/force-stop path
has been compiled and reviewed, not exercised in a live product run.
The final `--check` returned `ready=true launched=false`; compilation succeeded.
Its initial root-path representation rejection was fixed by using the same
standardized Foundation URL handling as the previous controller. Directory
ownership/mode, symlink rejection and empty-root checks remain required.

## Owner interaction

1. Prepare blank TextEdit and confirm readiness before any controller timer starts.
2. After launch, choose Start in the trial menu and accept local aggregate consent.
   Stop on any permission, restart, authentication or Keychain prompt; do not
   change permissions in this round.
3. Once Collecting is independently observed, receive the input instruction.
   In blank TextEdit, release all modifiers, then press left Command-A twice,
   releasing between presses. Use the mouse to select Pause in the trial menu,
   then return to chat and report completion.
4. Inspect the actual native statistics view while paused: Command-A ordinary
   count and exact modifier provenance, TextEdit application attribution, and
   visible paused status. Observe native accessibility labels and the rendered
   target window. Existing source identifiers include `phase2.stat.shortcut`,
   `phase2.stat.application` and the provenance disclosure.
5. Request normal Quit once observation completes; record aggregate/save outcome
   and confirm the exact App process is gone.

The trial can write only its isolated encrypted store/Keychain namespace.
Diagnostics retain coarse state and aggregate counts, with no typed text or
per-event stream. Native UI evidence may include only the trial window containing
these agreed synthetic input aggregates. No lock/sleep, permission toggle,
performance replay, network capture or daily-data access is in this round.

## Evidence and interpretation

Build/check logs:
`/private/tmp/keyrecord-phase1-ui-candidate-build.log` and
`/private/tmp/keyrecord-phase1-ui-controller-check.log`.
Controller output is `/private/tmp/keyrecord-phase1-ui-controller-run.log`.
Runtime outputs are `ui-privacy.jsonl` and `ui-summary.json` under the private root.
They are retained with `ui-quit.request` and must not be overwritten.
Native rows must be observed directly; total counters alone cannot establish
TextEdit attribution, modifier provenance or rendered/accessibility state.
If UI inspection is unavailable, record that part as missing and exit normally.

This round addresses current-candidate UI/attribution requirements. Complete
hosted Keychain lifecycle, independent system-lock authority and a qualified
collecting Release remain open. Existing performance and sleep observations are
retained without rerunning them.
