# Apple Silicon Phase 1 completion

Owner instruction: complete Phase 1 autonomously until a concrete step needs
owner cooperation. Work remains in the isolated PR #17 checkout. Public release,
Intel, packet capture and Phase 3/4 backends are outside this continuation.

## Completion criteria

Deliver a candidate whose capture, privacy closure, encrypted persistence,
restart/recovery, consent and aggregate presentation satisfy the existing
Phase 1 specification. Preserve existing fail-closed behavior and separate
observed candidate behavior from broader unverified claims. Do not merge PR #17.

The completed two-window ARM fixed-replay measurement and bounded lock/sleep
recovery remain evidence for their stated candidates; no routine repeat is planned.

## Work order

1. Reconcile the current remaining requirements against executable product code.
   Fix reproducible functional gaps and run focused regressions. In particular,
   verify the existing active-day encounter-order requirement across restart.
2. Complete the protected-read/publication observation needed for product
   lifecycle qualification. Existing gate-entry counts and presentation-model
   assignments must not be relabeled as exhaustive reads or actual rendering.
   Prepare the smallest real Keychain scenario supported by the actual observer.
3. Prepare a short isolated permission revoke/regrant and current UI/attribution
   check. Stop before launch for owner readiness and explain each action.
4. Reconcile results, then connect a collecting Release only after its real-path
   safety prerequisites are established. Run the final candidate source and
   executable capability audit; retain blocks when evidence is missing.

## Current state

- Starting commit: `e4dc8c655`; worktree clean at the start.
- Goal registered in this chat; not a declaration that Phase 1 is complete.
- Full hosted lifecycle observation is not wired. Actual permission changes and
  native UI verification require owner cooperation later.
- No new live capture, Keychain effects, permission changes or sleep/lock actions
  are authorized by this plan alone. Prepare code and a reviewable trial first.

## Active-day restart repair

A failing encrypted-store restart test reproduced the reducer restoring
Jan 2 / Jan 1 / Jan 3 encounters as Jan 1 / Jan 2 / Jan 3. The repair saves a
versioned encrypted `com.keyrecord.activeDayOrder` object per cycle through the
existing fenced writer. It precedes shards so interrupted writes cannot introduce
a durable day missing from the saved order. Recovery filters order entries whose
counts did not become durable; duplicate order entries, wrong cycles or missing
observed days fail closed. No keystroke sequence or per-event time is stored.

Cycle reset deletes this daily-detail object and keeps the existing summary
field set unchanged. Legacy data without order metadata remains readable using
the previous chronological fallback; missing historical order cannot be recovered.
The privacy serialization inventory includes the new three-field object.

The original reproduction failed as expected; 52 focused storage, reset/crash,
aggregation, privacy and recovery tests and all 553 SwiftPM XCTest cases pass.
App build-for-testing succeeds. All 69 selected product hostless recovery,
reduction and startup cases pass after updating two array-only test decoders to
assert the new order object separately from unchanged count assertions. Logs:
`/private/tmp/keyrecord-active-day-red.log`,
`/private/tmp/keyrecord-active-day-focused.log`,
`/private/tmp/keyrecord-phase1-completion-package.log`.
App build and test logs use `/private/tmp/keyrecord-phase1-completion-` with
`app-build.log`, `product-tests.log` (first run) and `reduction-tests.log` (rerun).
The earlier host measurements retain their original candidate bounds.

## Noninteractive Keychain queries

The product backend specification forbids authentication UI, but the product
SecItem identity omitted `kSecUseAuthenticationUI`. The installed Security SDK
documents that omission as allowing authentication UI. A new pure query test
failed for read, add and the shared update/delete identity. Product identities
now explicitly use `kSecUseAuthenticationUIFail`, retaining exact account/service,
data-protection Keychain and nonsynchronizable attributes. Interaction-required
access therefore takes the existing unavailable/locked error path.

All seven LocalKeychainQueries hostless tests and the Debug App test build pass.
No Security API operation was invoked by these tests. The separate signed-host
input and restart check below now exercises the updated query successfully.
Logs: `/private/tmp/keyrecord-keychain-ui-{red,build,tests}.log`.

## Completed input and restart check

The signed arm64 Debug candidate at `293f25a45` includes both repairs above.
The build used existing local signing assets without provisioning updates;
signature, profile and isolation checks pass. The candidate is staged at
`/private/tmp/keyrecord-phase1-next-candidate-20260929/build/Build/Products/Debug/KeyRecordApp.app`.
Build log: `/private/tmp/keyrecord-phase1-next-candidate-build.log`.
After the owner confirmed readiness, the installed MVP trial was replaced with
this candidate. Its previous bundle is preserved at
`/private/tmp/keyrecord-mvp-before-phase1-293f25a45.app`. The Performance Trial
was unchanged.

The owner-assisted check used **KeyRecord MVP Trial 20260929**, bundle
`com.keyrecord.trial.mvp20260929`, with fresh private root
`/private/tmp/keyrecord-phase1-closeout-live-20260929` and Keychain namespace
`com.keyrecord.trial.mvp20260929.phase1closeout1`. The owner confirmed Collecting
after Start/consent, then confirmed one Command-A in blank TextEdit. The controller
quit normally after input/save, then restarted for readback without further input.
This checks the new
Keychain query and persistence path; it does not reproduce a clock rollback on
the real machine or provide exhaustive protected-read observation.

Controller source and compiled executable are under
`/private/tmp/keyrecord-phase1-closeout-controller/Phase1Trial.swift` and
`/private/tmp/keyrecord-phase1-closeout-controller/Phase1Trial`.
`--check-input` passes without launch; `--check-readback` correctly rejects the
fresh root before input artifacts exist. The input stage requests normal Quit at
85 seconds with a 90-second exact-instance stop limit; readback uses 15/20 seconds.
Either stage can request early normal Quit via its private quit-request file.
Stop on any permission, restart or Keychain prompt; do not change permissions.
No lock/sleep, network observation or daily-data access is part of this check.

Input recorded one key-down, one key-up and two modifier callbacks, four accepted
handoffs and aggregate delta one. Published totals were one shortcut and zero bare
keys. All four issued writes returned successfully and were recorded durable;
there were no write failures, timeouts, invalidations or snapshot read failures.
The restarted process published the same totals with zero callbacks, handoffs,
aggregate delta or writes, and 13 successful snapshot publications. Both controller
processes exited zero after normal Quit; final quit action details reported Stopped
and no live session. Exact PID checks confirmed both App processes (73689, 73858)
were gone. Top-level diagnostic `captureSessionLive` is a non-atomic pre-cleanup
sample; it is not evidence that capture remains active after process exit.

Artifacts are `input-summary.json`, `readback-summary.json` and their corresponding
`*-privacy.jsonl` files under the private root. Controller logs are
`/private/tmp/keyrecord-phase1-closeout-{input,readback}-controller.log`.
Both CI builds for documentation head `e808d6483` succeeded:
[PR](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36546858162) and
[push](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36546850292).

This completes the bounded fresh-store physical-input/save/restart-readback check
on `293f25a45`. It does not identify a specific application/shortcut row from
aggregate-only evidence or exercise interaction-required Keychain failure. The complete
hosted protected-read/publication observer, actual permission revoke/regrant,
native UI/attribution checks and qualified collecting Release composition remain
open. Earlier sleep and performance evidence remains bound to its recorded
candidates and does not automatically qualify `293f25a45`.

## Next segmented permission check (prepared, not launched)

Use the same installed `293f25a45` MVP trial, private root and namespace above.
The local controller now has separate `--permission` and `--recovery` modes;
each requires its predecessor's summary and refuses existing output names.
Check variants never launch. No product source changed after the input/readback
round. Preserve that round's artifacts.

1. Wait for explicit owner readiness before launching the permission segment.
   Confirm Collecting and granted permission. Ask the owner to open Input
   Monitoring and turn off only the exact MVP Trial entry, leaving the Performance
   Trial alone. Observe actual denied permission plus capture closure and hidden
   state; a generic source stop alone is insufficient.
2. If macOS requests Quit and Reopen, the owner leaves the dialog alone and reports
   it. Request normal Quit through the isolated controller before any relaunch;
   never use the system's environment-free reopen as product acceptance. Any
   authentication or unexpected Keychain prompt ends the segment. The permission
   segment requests normal Quit at 175 seconds, exact-instance stop at 180 seconds.
3. With the trial confirmed stopped, ask the owner to re-enable only that entry.
   Wait for a fresh readiness confirmation. Launch `--recovery` with explicit
   isolation (normal Quit at 85 seconds, exact-instance stop at 90 seconds).
   Verify fresh permission and protected-store readiness, then Collecting after
   any required Start/consent. Request one Command-A in blank TextEdit, check new
   aggregate/save, and request normal Quit early.

New outputs are `permission-{summary.json,privacy.jsonl}` and
`recovery-{summary.json,privacy.jsonl}` in the existing private root. No sleep,
lock, packet observation, daily data or signing-account changes are included.
No deadline is extended; an incomplete segment remains incomplete. This tests
revocation and explicit isolated recovery across processes, not same-process
regrant or full hosted Keychain lifecycle. Native rendered row attribution and
the full observer still need separate evidence. This record alone authorizes no
new live launch or permission change.
