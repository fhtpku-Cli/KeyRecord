# Bounded collecting Release input round

The installed Apple Silicon Release product from
`ea90753feab2358166ee39384bb6a5501dc4ce64` completed one owner-coordinated input/UI
round. It runs as **KeyRecord Release Trial**, Bundle ID
`com.keyrecord.phase1.probe.host`, with the existing development signing profile.
The subsequent `c337c68475894d724888c80e85c95e626918a303` changes only tests/docs.
Both remote CI checks on that commit pass:
[push build](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36759158642/job/110036952648)
in 6m50s and
[PR build](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36759165910/job/110036978071)
in 6m16s. The earlier watch command itself hit a GraphQL timeout; a later direct
check confirmed the jobs' successful terminal states. No CI rerun was triggered.

## Observed input and interface

The owner enabled the new trial identity's Input Monitoring and confirmed readiness.
The controller then launched exact PID 84432, with no existing same-identity process.
The owner confirmed **Collecting** after Start/consent. The requested sequence was
two complete left-Command hold, A press, both-keys release actions in blank TextEdit,
followed by mouse Pause and opening Settings > Aggregates. There was no extra
Command-only priming press.

The owner supplied an actual product-window screenshot showing:

- Shortcut total **2**; bare-key total **0**.
- `Command (side unknown)-Key 0 · App: com.apple.TextEdit`: **1 observed**,
  ordinary source.
- `Command (left)-Key 0 · App: com.apple.TextEdit`: **1 observed**,
  ordinary source.

This proves the bounded real-input aggregate rendering and TextEdit attribution.
It does not prove two left-side observations or event ordering. The screenshot
does not include the menu state. The owner subsequently confirmed that Pause was
not clicked and its state was not checked. This round therefore supplies no Pause
evidence. Additional keyboard activity between the screenshot and normal Quit
could have changed global totals; the displayed two is not a measured final durable
total. A later readback must preserve the pictured TextEdit buckets, while reporting
the actual recovered totals rather than assuming they remain exactly two.

One unknown side is consistent with the existing conservative reconstruction rule:
after reset, an active family plus one side's flagsChanged cannot distinguish a
press from a release while the other side remains held. An observed fully released
family restores a known starting point; a subsequent coherent left press can then
be labeled left. The already-passing
`ModifierRecoveryTests.testFirstPressAfterReopenRemainsUnknownUntilReleaseThenRecoversLeft`
exercises this exact transition, including another revoke/reopen. The aggregated
screenshot alone cannot establish which physical input produced either row.
No code change to guess sides, historical-data rewrite or priming rerun is warranted.

## Exit and storage boundary

After reviewing the screenshot, the exact-PID/path/identity helper requested normal
application termination. The controller records exit **0**, **141.014 seconds**,
`forced: false`, with no deadline or stop reason. A subsequent native process query
found zero same-identity applications. The one-use round is consumed; do not reuse
its directory or silently relaunch.

Read-only file metadata inspection found the trial's native store directory at
`~/Library/Application Support/com.keyrecord.phase1.probe.host/store` with mode 0700,
four opaque regular `.krenc` files plus `manifest.krenc`, all mode 0600. No file
contents were decrypted by the observer and no Keychain bytes were read or logged.
These file facts and normal exit do not independently prove a fresh-process decrypted
readback of the two counts. Earlier real composition/restart evidence retains its
own scope. The trial's store and Keychain items are retained; no cleanup deletion,
sleep, lock or packet capture occurred in this round. No manual login-item toggle
was requested; Start uses the real login-item backend and its registration outcome
was not independently observed.

Controller record: `/private/tmp/keyrecord-release-input-round-20261001/result.json`.
Owner screenshot: `/var/folders/3h/fv0ztbr93q7_115hvwrhbrnh0000gn/T/codex-clipboard-f50770d3-11aa-40eb-b711-5531e78d70ab.png`.
Independent result review: `/private/tmp/.omo/evidence/release-live-input-result-review.md`.
Signing/build/controller preparation: [candidate record](RELEASE_CANDIDATE_20261001.md).

## Prepared follow-up procedure

After fresh owner readiness, reopen the same installed candidate. Since the prior
session was not paused, automatic Collecting can be the expected persisted intent;
this is not a read-only launch. The owner should immediately use the mouse to Pause,
confirm Paused, then inspect Aggregates without entering test keys. Preserve the
two pictured TextEdit buckets and record any additional counts without inventing
their origin. Normal Quit then ends the bounded round. This combined restart/readback
and real Pause check does not require another paused-boot round merely to follow
the earlier plan. The existing T23 signed-host walkthrough remains separate.

## Actual new-process readback

After fresh readiness, the controller reopened the unchanged installation as PID
89085. The owner reported verbatim that it opened directly as Paused and supplied
a new screenshot. It shows shortcut total 2, bare-key total 0, TextEdit Key 0 unknown
Command 1 and left Command 1, both ordinary source, matching the prior screenshot.
No Start/Resume or new test keys were requested. The owner did not need to click
Pause in this round; the report is an observed state, not a Pause-button action.
The reason it started Paused is not established by these observations. Do not
attribute it to a particular preference write or privacy transition, and do not
claim a continuously instrumented zero-admission interval.

The fresh-process persisted aggregate readback passes. Normal Quit was requested
after inspection; the controller exited 0 in 81.534 seconds with `forced: false`
and no stop reason. A subsequent native query found zero same-identity instances.
No additional input or restart is needed to repair the difference from the planned
procedure. The then-remaining [T23 walkthrough](RELEASE_NATIVE_UI_PREP_20261001.md)
subsequently completed with owner-confirmed focus/speech/display observations,
normal exit and restoration of the changed system settings.

Readback record: `/private/tmp/keyrecord-release-readback-round-20261001/result.json`.
Screenshot: `/var/folders/3h/fv0ztbr93q7_115hvwrhbrnh0000gn/T/codex-clipboard-a5a33eb3-9b89-44da-b3be-c36a613e1063.png`.
Independent review: `/private/tmp/.omo/evidence/release-readback-result-review.md`.
The preceding documentation commit `2b2d365d` also passed both remote jobs
[push](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36761090417/job/110043515783)
in 5m27s and [PR](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36761096060/job/110043533794)
in 7m35s.
