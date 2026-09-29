# Prepared current-candidate UI and attribution check

Status: preparation only. Owner approval/readiness for this exact round is
required before installation or launch. No current UI PASS or new live collection
is claimed by this document.

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
Runtime outputs, if authorized, will be `ui-privacy.jsonl` and `ui-summary.json`
under the private root. They must be preserved even if the round is interrupted.
Native rows must be observed directly; total counters alone cannot establish
TextEdit attribution, modifier provenance or rendered/accessibility state.
If UI inspection is unavailable, record that part as missing and exit normally.

This round addresses current-candidate UI/attribution requirements. Complete
hosted Keychain lifecycle, independent system-lock authority and a qualified
collecting Release remain open. Existing performance and sleep observations are
retained without rerunning them.
