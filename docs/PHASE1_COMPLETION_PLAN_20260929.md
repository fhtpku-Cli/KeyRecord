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
The installed trial Apps and their candidate-bound host measurements are unchanged.
