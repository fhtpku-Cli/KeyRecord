# Permission and recovery candidate prepared, not launched

Signed arm64 Debug source `fde8c888684b0b13c6e23f4081a94ecc10fa1915` contains the
failed-recovery settlement and tri-state permission witness repairs. The build
used only existing local signing assets for team `P3W62C39TN` and bundle
`com.keyrecord.trial.mvp20260929`, without provisioning updates.

Candidate: `/private/tmp/keyrecord-phase1-permission-candidate-20260930/build/Build/Products/Debug/KeyRecordApp.app`.
Log: `/private/tmp/keyrecord-phase1-permission-candidate-build.log`.
The build script and controller's no-launch permission checks both succeed.
The installed `KeyRecord MVP Trial 20260929.app` remains source `426969c9f`;
installation must preserve that bundle before replacement. Performance Trial is
outside this operation.

Controller source/executable:
`/private/tmp/keyrecord-phase1-permission-controller-20260930.swift` and the same
path without `.swift`. It compiled with `-parse-as-library` and a private module
cache. It reuses the completed chord round's private root
`/private/tmp/keyrecord-phase1-chords-live-20260930` and exact namespace
`com.keyrecord.trial.mvp20260929.phase1chords20260930`, retaining the two durable
shortcuts. New output names are `permission-{summary.json,privacy.jsonl,quit.request}`
and `recovery-{summary.json,privacy.jsonl,quit.request}`. It refuses existing stage
outputs, checks stage prerequisites, refuses an existing same-bundle process and
bounds only the launched instance. Recovery's preflight currently rejects the
missing permission summary, as intended. No artifact was invented to bypass it.

## Proposed owner-assisted procedure

Fresh approval covers installation, reuse of this trial-only encrypted store and
Keychain namespace, and the following two separately readied segments. It does
not authorize a launch before readiness or a repeat of either consumed segment.

1. Prepare blank TextEdit. After installation and isolated launch, use Resume if
   the persisted state is Paused; otherwise use the actual Start action and consent.
   Wait for verified Collecting; no test key is required in the first segment.
2. Toggle off only MVP Trial's Input Monitoring. If macOS offers Quit and Reopen,
   stop at that prompt and report it; the controller requests normal Quit. Do not
   use an environment-free automatic relaunch. Stop on authentication/Keychain
   prompts. This segment requests Quit at 175 seconds, with an exact-instance
   stop at 180 seconds; it can end earlier by private quit request.
3. With the App closed, restore only that permission and confirm readiness.
   The isolated recovery segment requests Quit at 85 seconds and stops at 90.
   After verified permission and explicit Start/Resume, hold left Command while
   pressing A once, release both keys, then Pause with the mouse and report.

Acceptance requires a fresh explicit denied witness, capture/key closure, and
unchanged sampled counters; unknown or historical NotGranted is insufficient.
Recovery must independently observe granted permission, explicit user activation,
one new shortcut and durable total three. A restarted-process result does not
establish same-process regrant, continuous privacy or full hosted qualification.
No lock/sleep, packet capture or daily-store access is included.
