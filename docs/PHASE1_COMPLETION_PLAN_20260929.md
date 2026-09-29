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

## Segmented permission check (both segments completed; evidence limits remain)

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

The owner subsequently confirmed this round and reported Quit and Reopen after
turning off the exact trial entry. The isolated process (88564) had reached
Collecting with granted preflight. It then closed with `privacyCheckRequired` /
`tapUnavailable`; all 19 closed observations kept capture stopped and sensitive
state hidden, with unchanged aggregate, handoff, normalization, durable-write,
protected gate-entry and snapshot/analysis attempt/publication counters. Shortcut
total remained one. One write succeeded before closure, with no read/write failure.
Normal early Quit exited zero, and an exact PID check confirmed termination.
Artifacts: `permission-summary.json` and `permission-privacy.jsonl` in the private
root, plus `/private/tmp/keyrecord-phase1-closeout-permission-controller.log`.

No product preflight-denied witness was recorded before source closure. A narrowly
scoped read-only system TCC query was denied access; no permissions were changed
to obtain it. Thus this is observed fail-closed behavior following the owner's
reported toggle, not independent proof of a denied TCC state or completed formal
permission acceptance.

The owner then re-enabled the same entry and explicitly confirmed readiness.
The isolated recovery process (89284) observed granted permission and reached
Collecting. One confirmed Command-A produced one key-down/up and two modifier
callbacks, aggregate delta one, and shortcut total two (previously one), with zero
bare keys. Both issued writes succeeded durably; there were no write/read failures,
timeouts or invalidations. Early normal Quit exited zero, final action details
reported Stopped/no live session, and an exact PID check confirmed termination.
Artifacts: `recovery-summary.json`, `recovery-privacy.jsonl`, and
`/private/tmp/keyrecord-phase1-closeout-recovery-controller.log`.
Permission was restored and freshly checked as granted in this new process.
No automatic system reopen, lock/sleep or daily-data operation was performed.

The bounded user-toggle/closure and separately readied regrant/restart/input/save
flow is complete on `293f25a45`. It is not same-process regrant evidence, an
independent denied-state witness, continuous protection or full hosted lifecycle
qualification.

## Closed-interval permission diagnostic repair

A hostless regression reproduced the journal gap: disable the event tap while
permission is granted, wait for capture/protected state to close, then change the
injected permission to denied. The collecting-only monitor has already stopped,
so no not-granted witness arrived and the test failed. The existing explicitly
enabled Debug closed-interval sampler now also calls the noninteractive permission
preflight and records its existing granted/not-granted witness. It rechecks task
cancellation and interval state after the asynchronous provider reads. This neither
requests permission nor restarts capture, accesses protected data or changes
Release behavior. Not-granted includes unknown; it must not be labeled denied
without stronger evidence.

The regression now verifies denied then granted observations while remaining
Blocked, with capture/key gate closed, sensitive state hidden and no aggregate
change. All 57 hostless product recovery/quit tests and 16 resource-interval
evaluation tests pass; Debug build-for-testing succeeds. Logs:
`/private/tmp/keyrecord-closed-permission-{red,red-build,build,tests,interval-tests}.log`.
The installed signed candidate and original host artifacts remain unchanged at
`293f25a45`; this diagnostic change is not retroactive live evidence. No repeat
physical round has been started or newly authorized.

## Protected-read observation: first executable coverage increment

Debug product composition now attaches process-wide low-level read activity to
its existing journal and run summary. `AuthenticatedStorageEnvelope.open` records
entry to and completion of the actual AES-GCM open operation, including an
authentication failure. `LocalKeychainBackend.read` records the real
`SecItemCopyMatching` call, including a failed/not-found response. Metadata and
version probes use that same exact-item read method. No key, plaintext, object
identity, event or timestamp is recorded. Four monotonically increasing counts
are read under one lock; overflow makes the observation absent. They cover all
stores in the process, rather than quietly excluding another store's activity.

The existing offline closed-interval evaluator consumes these counts when present.
New operations within the interval are violations. A read begun before closure
and still in flight at a sampled boundary is inconclusive, not zero activity.
Partially missing, inconsistent or decreasing observations cannot pass that check.
Old journals retain their original limited interpretation; no old result acquires
every-read, rendering or continuous-closure claims.

Validation: all 562 SwiftPM XCTest cases and 57 hostless product recovery/quit
tests pass; Debug App test build and native arm64 unsigned Release build succeed.
Tests cover actual successful and failed decryption, concurrent counter updates,
pending reads, overflow, journal encoding and interval evaluation. The actual
Security operation is instrumented in source but has not been rerun on a signed
host candidate. The fresh Release executable excludes `ProtectedReadActivity`
symbols/strings and passes the existing static network-capability audit with zero
matches. This is build/audit evidence, not a collecting Release or signed launch.
Logs: `/private/tmp/keyrecord-protected-read-{package-tests,app-build,app-tests,release-build,release-audit}.log`.

This first increment does not implement the complete hosted observer. The next
increment below adds cached reads. Native rendering remains a separate check.

## Cached and aggregate read observation

Debug observations now include cached manifest/key-material access and nonempty
in-memory reducer access, for eight start/completion counters in total. The same
process-wide observer covers cached access that does not decrypt again. Closed
store rejection, empty staging and clearing state do not count as payload reads.
The evaluator accepts complete legacy four-field observations or complete new
eight-field observations; partial or changing coverage is inconclusive. It still
does not claim exhaustive read coverage, actual rendering or continuous closure.

The product-path closure regression asserts all eight counters are present,
balanced and unchanged at closure, closed samples and explicit reauthorization.
It passes with synthetic dependencies. All 57 recovery/quit and 10 reduction
tests pass. The 564-case package run had one source-length check failure after
adding helpers to ObjectStore; extracting them into an extension preserved that
check, and all 175 affected storage tests then passed. No failed test was removed
or weakened. Final Debug test and native arm64 unsigned Release builds pass;
Release excludes the observer symbols/strings and its static network audit has
zero matches. Logs use `/private/tmp/keyrecord-cached-read-` with
`package-tests.log`, `store-rerun.log`, `recovery-tests.log`, `reduction-tests.log`,
`boundary-test.log`, `final-debug-build.log`, `final-release-build.log` and
`release-audit.log`.

Remaining observation work includes plaintext processing, publication coverage and connecting observations to
the hosted lifecycle controller with its independent lock witness. These counts
must not yet populate an exhaustive hosted protected-read claim. The installed
signed App remains `293f25a45`; no new host, permission, lock/sleep or performance
round was run.

## Preserve authorization through aggregate serialization and staging

The source audit found that ProductFlush took an authorized reducer copy, then
serialized it after releasing the protection lock. Scheduler staging also adopted
the scheduler's current generation rather than the generation that produced that
copy. A closure/reopen between those steps could therefore admit an old batch to
the new session. Serialization now executes inside the existing reducer/key gate;
the batch carries that generation into staging, which rejects a mismatched current
session. Failed serialization or generation invalidation leaves the reducer dirty
for retry. Preference decode/encode after awaits now also uses the original key
generation's existing protection scope. No new gate or persisted state was added.

Regression tests verify rejection of a pre-closure batch after scheduler reopen,
zero resulting writes, acceptance of a fresh batch, and dirty-state retention after
serialization failure or generation revocation. All 176 Store, 20 interval
evaluation and 5 read-observer tests pass, as do 11 product reduction and 57
product recovery/quit tests. Debug test build and unsigned native arm64 Release
build pass; the latest Release static network audit has zero matches. Logs:
`/private/tmp/keyrecord-staging-generation-{store-tests,reduction,recovery,build,release,release-audit}.log`.
This closes the identified staging race in code; it does not extend live evidence
or declare complete protected-read observation. The next work remains the full
observer and publication boundary, followed by a separately coordinated host run.

## Presentation access during delayed lifecycle updates

A product-composition regression reproduced cached aggregate and analysis reads
and new publications after the key gate closed while lifecycle state still said
Collecting. The original test produced seven assertion failures. This is the
interval between synchronous privacy revocation and the queued main-actor update;
checking lifecycle visibility alone was insufficient.

Product composition now gives its flow observable the same existing key gate.
Aggregate and analysis publication/read execute under that protection. Each cached
presentation retains its producing generation, so closing and reopening the gate
without a fresh publication cannot expose the previous generation. Clearing state
remains possible while closed. Debug aggregate-read observations now also cover
reads at the presentation model boundary; nil returns may conservatively count
when access is authorized. Rejected closed/stale accesses do not read payloads or
increment successful publication counts. Fixture-only flow models can continue
without a store gate; the actual product composition always supplies its gate.

All 89 selected hostless tests pass: 58 recovery/quit, 11 snapshot publication,
14 flow and 6 paused-startup cases. The new case also verifies fresh publication
after reauthorization and rejects stale cached data after a later close/reopen.
Its fixture now waits for its preparation write before taking the before/after
counter samples; the focused rerun passes. Debug test and unsigned arm64 Release
builds pass, and the Release static network audit has zero matches. Logs:
`/private/tmp/keyrecord-presentation-gate-{red,regressions,fixture-test,final-build,fixture-build,release,release-audit}.log`.

These are model access/publication results, not a claim about already rendered
pixels or a complete hosted lifecycle observer. Full plaintext-processing coverage,
the hosted controller connection and native UI/attribution checks remain open.
The installed signed candidate remains `293f25a45`; no new live run occurred.

## Plaintext-processing observation

The Debug read-activity record now has ten fields. The added start/completion pair
covers synchronous protected work in the existing key gate, aggregate encoding,
canonical identity parsing, manifest/Keychain metadata coding and validation,
reset payload/journal coding, object binding, key derivation and encryption.
`ProtectedProcessing.observe` executes the same closure directly in Release;
the counter state and diagnostic fields are Debug-only. No gate, cryptographic
format, key policy or persisted product object was added or changed.

These are conservative processing scopes: they overlap lower-level read counts
and can include validation or a scope that ultimately has no payload. Do not sum
them as a count of distinct data reads. They make work spanning a sampled closed
boundary visible instead of treating completed decryption as completed processing.
The evaluator identifies processing begun inside a closed interval and reports
in-flight processing as inconclusive. Complete four/eight-field historical logs
retain their previous limited interpretation; partial, mixed or missing groups
cannot masquerade as a complete older format. Exhaustive-read, rendered-pixel
and continuous-closure flags remain false.

Actual decoder tests observe a pending scope from inside `Decodable.init`, then
verify balanced completion both on success and failure. Manifest validation and
encryption tests demonstrate processing without a decryption. Stale key-gate
scopes do not execute their body. The broad package run passed all 570 cases;
after extending key-derivation/object-binding coverage and adding one test, all
221 affected cases passed (180 Store, 22 measurement, 14 integration and 5 Core).
All 80 selected product tests passed; the final two focused product regressions
also pass with all ten counters present, balanced and unchanged while closed.
Final Debug test and unsigned native arm64 Release builds pass. Release symbols
and strings contain no `ProtectedReadActivity` or processing counter field, and
the static network audit has zero matches. Logs use
`/private/tmp/keyrecord-plaintext-observation-` with `package.log`,
`boundaries.log`, `app-tests.log`, `final-store.log`, `final-app-tests.log`,
`final-app-build.log`, `final-release.log` and `final-release-audit.log`.

The starting-boundary concern identified here is addressed by the next increment.
The hosted observer/independent-witness connection remains open. No signed trial,
lock/sleep or performance round was launched.

## Observe reads from synchronous revocation — 2026-09-30

A failing-first product test closed the existing key gate while the main actor
still showed Collecting, then deliberately encrypted synthetic bytes before the
delayed journal begin. The original journal lacked a revocation-time observation,
so that work could disappear into its initial counters. This is an offline
diagnostic reproduction, not an observed live leak.

Debug now snapshots the ten process-wide read/processing counters under the
existing key-gate mutex immediately before changing an open gate to closed.
Repeated closed-state updates retain that observation; reopening clears it.
Normal generation renewal leaves no closed observation. The synchronous path
performs no journal I/O or recorder callback, avoiding a reverse lock order with
the journal's gate reads. The later begin includes the saved counts separately
from its current counts; missing or overflowed revocation evidence is inconclusive.

The evaluator includes the saved observation when checking increases, in-flight
work, coverage and monotonicity. It detects all five instrumented operation kinds
between revocation and delayed begin. Legacy journals keep their original limited
meaning. Exhaustive protected-read, continuous closure and rendered-pixel claims
remain false; these counters do not provide an independent OS lock witness.

Validation: 47 focused package cases pass (6 protected-processing, 25 measurement,
4 privacy serialization, 12 diagnostic counters), as do all 59 product recovery
tests, including the initial three boundary regressions. Debug test build and unsigned native arm64 Release build
pass. Release symbols/strings exclude the new observation and the existing static
network audit reports zero matches. Logs use
`/private/tmp/keyrecord-revocation-observation-` with `red-build.log`, `red.log`,
`final-package.log`, `app-tests.log`, `final-app-build.log`, `final-app-tests.log`,
`release.log` and `release-audit.log`. The installed signed trial is unchanged.

## Observe actual capture admission — 2026-09-30

The hosted controller still has no real product-observer implementation or
independent system-lock authority. While checking that integration, a product
regression reproduced another missing input: `captureSessionLive` is a lifecycle
mirror that can remain true after synchronous revocation. It cannot establish
the actual event queue or key gate state for a host observation.

The Debug recorder now reads `captureQueueOpen` directly from the product queue
and `keyGateOpen` through the existing key gate's non-reading availability check.
These optional booleans accompany run summaries and privacy journal samples.
The callbacks execute outside the recorder mutex. Unconfigured observations remain
absent, and the existing non-atomic sample designation remains unchanged.
Closed-interval evaluation detects an observed open queue or key gate and rejects
partial state coverage. Historical logs retain their narrower original meaning.

The failing-first product test produced six missing-field assertions. After the
repair, it observes queue-open/key-closed before queue revocation and both closed
afterward, while the lifecycle mirror still says live. The existing product
closure/recovery test now checks both actual states at begin, during and end.
Both product tests and 43 focused package tests pass (26 measurement, four privacy
serialization, 13 diagnostic counters). Debug and unsigned arm64 Release builds
pass, Release contains neither the recorder nor new field strings, and the
existing static network audit reports zero matches. Logs:
`/private/tmp/keyrecord-admission-observation-{red,red-build,package,app-build,app-tests,release,release-audit}.log`.

These observations are sampled state, not continuous closure or an independent
OS witness. No hosted lifecycle PASS or collecting Release is claimed. The next
owner-assisted check will inspect the current candidate's actual native aggregate
rows and status; the completed performance and sleep rounds are not repeated.

The separately approved/readied signed `346dc26d8`
[current UI/attribution round](CURRENT_UI_TRIAL_20260930.md) is now complete with
partial evidence: two owner-confirmed shortcuts, aggregate delta/totals two,
six successful durable writes, paused queue closure and normal Quit. The exact
trial PID is gone. Native Computer Use disconnected before returning any UI,
so actual rows, attribution, rendering and accessibility remain unverified.
The occupied private root and original artifacts are preserved; no automatic
repeat is authorized. Resolve the native observation limitation before another
UI round. Full hosted lifecycle/independent lock authority and Release remain open.

The separately approved/readied paused readback of the same candidate completed
without repeated input: two shortcut totals restored, zero callbacks/handoffs/new
aggregate delta/writes/read failures, closed capture in all five journal records,
then normal Quit and exact PID gone. The owner opened the aggregate tab; native
observation still disconnected. The owner replied `2次，是的`; the exact TextEdit and
modifier-provenance scope is awaiting clarification. No complete rendering or AX
PASS is claimed. Pure regular/accessory controls worked, while a windowless
control timed out without the exact crash; these do not qualify the product UI.
See the current UI trial record for the consumed output paths and full result.
