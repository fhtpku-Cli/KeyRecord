# Phase 1 remaining acceptance

Current status: [PROJECT_STATUS.md](PROJECT_STATUS.md). Requirements: [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md) and architecture §12.4/15. This matrix separates executable regression coverage from host qualification; it is not a new gate or acceptance receipt.

**Current MVP scope (2026-09-29):** The first usable capture MVP may target native Apple Silicon only. Intel compatibility and Intel performance are later complete G1/v1 work, not reasons to block this MVP. A provisioned Debug trial has initialized protected storage, recorded 3 physical shortcuts with 4 issued/4 durable writes and read back the same total after restart with no new input or read failure. The signed `a604ad535` Debug fixed-replay candidate now completes the agreed short native ARM typing/idle performance measurement within budget ([result](PERFORMANCE_SHORT_ROUND_20260929.md)); this does not qualify event-tap overhead or Release. Complete Keychain lifecycle, full privacy recovery and a qualified collecting Release remain unverified. The historical full G1 requirements and prior candidate-specific results below retain their stated scope; this decision does not turn a missing measurement into PASS.

## Evidence and remaining work

The [integrated Release dependencies](RELEASE_CANDIDATE_20261001.md) now build
with the measured Keychain implementation and exact observed-platform qualification.
127 App tests, six core isolation tests and actual Release static audits pass.
Release default storage is Bundle-ID-specific; the fixed daily-root trial exclusion
remains enforced. The Phase 1 aggregate surface now passes ten native UI/modifier
tests and both locale rendering checks. Signed Release `ea90753f` has now completed
the [bounded input/UI round](RELEASE_INPUT_ROUND_20261001.md): two TextEdit shortcuts,
zero bare keys, unknown Command 1 / left Command 1 and normal exit. All 591 package
tests and both remote CI jobs on `c337c684` pass. A subsequent fresh process recovered
the same two TextEdit records, opened directly as Paused according to the owner,
and exited normally in 81.534 seconds. This is not evidence of clicking Pause or
of why startup was Paused. Both CI jobs on documentation follow-up `2b2d365d` pass.
Only [T23's real Tab/Shift-Tab, VoiceOver, system
Increase Contrast/Reduce Motion and native status-menu positioning checks](RELEASE_NATIVE_UI_PREP_20261001.md) remain. The ten
focused native tests are not a complete T23 result; no repeated input priming,
lock/sleep/performance or Keychain destruction round is required.

The [real key integrity/deletion round](PRODUCT_KEY_INTEGRITY_20261001.md) passes
on signed `1b82d7cd`: one case, zero failures/skips/runtime warnings, normal exit
in 12.154 seconds without a remaining host. Missing and corrupt keys preserve
encrypted files and prevent capture/replacement mutations; original-key recovery
reads two counts. The product deletion flow removes store and both items before
fallback cleanup. This closes the bounded FR-P7 real-backend composition case;
login-item effects and input were simulated, so native controls and system login
unregistration are not established by this result.

Shared product safety wiring (2026-10-01): lock notifications, startup protection
and manual-entry checks now compile through one Debug/Release path. The suspended
startup-read regression failed before repair (gate open and backend query), then
passed after reusing the existing recovery fence for atomic current-attempt
reopening. All 114 selected App tests and seven core recovery tests pass. App
recovery fixtures exercise `ProductHostBoundaries.qualification` without developer
armament; a separate negative case confirms unqualified assembly makes no Keychain
queries or capture admission. Debug/Release arm64 builds and actual Release static
capability/network audits pass. These are offline integration results; the factory
was blocked at that extraction checkpoint. The subsequent dependency selection
above still awaits the remaining integrated candidate checks.

The [raw Keychain lock measurement](RAW_KEYCHAIN_LOCK_PREP_20261001.md) completed
with owner-confirmed screen lock: one real case passed, raw read returned 0 and
the expected fixed value, the instrumented product remained closed, and all three
owned items were cleaned up. No host or runtime warnings remain. This closes the
bounded raw-policy measurement gap, not collecting Release or all privacy/UI proof.

Current preparation: the [version-scoped provider](OBSERVED_LOCK_PROVIDER_20261001.md)
is shared with Release compilation, restricted to the observed native arm64
macOS 27.0 build 26A428. The original contract permits this observed candidate;
a public-only replacement API is not an added prerequisite. Full lifecycle and
collecting Release qualification are still incomplete.

The [existing-store locked-restart round](PRODUCT_LOCKED_RESTART_PREP_20261001.md)
now passes on signed `0766c515`: two real cases pass with zero failures/skips and
no recorded runtime warnings. Different seed/restart PIDs save two, start locked
with zero guarded Keychain attempts, restore two after unlock and save three.
Both owned items are cleaned up; total controller time is 53.383 seconds with
normal exits and no probe. This supplies the bounded separate-process proof,
while production lock authority, raw locked Keychain semantics and Release remain
open. The fixture also has 21 offline passes and six real opt-in skips.

The [coordinated lock-source observation](LOCK_STATE_SOURCE_PREP_20260930.md)
recorded 58 fresh processes across unlocked/locked/unlocked with owner confirmation.
The [product locked-startup fixture](PRODUCT_LOCKED_STARTUP_PREP_20260930.md) passes
offline with zero locked Keychain attempts and subsequent counts 2/2/3. Eighteen
offline cases pass; all three actual Keychain opt-ins skip. The subsequent signed
`3174772037` round passes the fresh-install scenario: one passed, zero failed/skipped,
zero guarded Keychain attempts while locked, counts 2/2/3 after unlock, cleanup of
both owned items and no remaining host. Its xcresult retains a Security main-thread
runtime warning, addressed separately in test source. This does not qualify
existing-store process restart under lock, production lock authority or collecting
Release.

The preceding reviewed round reuses unchanged signed `fee7d4aef` after owner unlock:
one full-product real Keychain case passed, zero failed/skipped, no runtime warnings.
It saves two simulated inputs, recovers two, reconstructs the composition in the
same process and saves three. Both owned items are cleaned up; the controller exits
normally in 12.236 seconds with no remaining host. This qualifies that bounded
unlocked recovery path, not actual OS lock authority, startup/process restart under
lock or collecting Release. See the [current result](PRODUCT_COMPOSITION_ROUND_20260930.md#current-result-unlocked-full-product-scenario-passed).

Earlier diagnostic execution on the same source failed at Keychain add `-25308`,
created zero items and exited normally. A subsequent check saw the host locked;
that check does not establish the lock state at failure time. The earlier records
below retain their checkpoint scope; real product execution is now covered above.

The [first signed full-product case](PRODUCT_COMPOSITION_ROUND_20260930.md) failed
with a generic timeout, then exited normally with no remaining host. Signing and
static identity checks passed, but this does not qualify real product recovery.
The diagnostic follow-up separates failed startup from a generic wait timeout.

The [full product hosted assembly](PRODUCT_COMPOSITION_HOST_PREP_20260930.md) now
connects actual composition, encrypted storage and counter observation in the
existing probe. Sixteen offline hosted cases and 138 lifecycle cases pass, with
two real-Keychain cases and one optional signed-disk fixture explicitly skipped.
Debug/Release probe builds pass. This supersedes the older assembly-pending
preparation below; real product Keychain execution and independent lock authority
remain unverified.

The [Secure Input rebuild race repair](SECURE_INPUT_RECOVERY_RACE_20260930.md)
passes a deterministic failing-first regression and all 65 product recovery/quit
cases. The product observer and missing-material recovery now exercise the actual
backend's metadata inventory/read path over a memory Security client. Native
Release compiles with its existing restrictions; live recovery remains separate.

The subsequent owner-approved [real Keychain round](PRODUCT_KEYCHAIN_ROUND_20260930.md)
passed the actual App backend's isolated unlocked CRUD, policy-attribute and cleanup
case on signed `25ef0f117`: one passed, zero failed/skipped, normal host exit.
This supersedes the earlier unrun status below only for that bounded case.
Locked-state behavior, full product recovery and collecting Release remain open.

The latest [hosted backend integration](PRODUCT_KEYCHAIN_HOST_PREP_20260930.md)
executes the real App backend against an injected in-memory Security client in
offline tests. Per-operation authorization, exact namespace/policy constraints,
CRUD, metadata conflict, inventory and error mapping are exercised. The opt-in
real Keychain test is prepared but unrun. Matching probe profiles were obtained
in one approved build of `b889640b4`. Static inspection then reproduced a
preflight error requiring independent process entitlements on a test plug-in;
the offline repair and its exact signed-file regression pass. A separately
approved signed rebuild at `25ef0f117` now includes that repair and passes its own
read-only signature/role inspection. Neither signed host has been launched.
The private bounded controller passes synthetic timeout/error cleanup and its
read-only preparation check; the real Keychain round still requires approval.
This supersedes the query-only preparation below, without claiming real Keychain
accessibility, full product recovery or live lock qualification.

Latest [approved permission/restarted-recovery round](CURRENT_PERMISSION_TRIAL_20260930.md)
on signed `fde8c8886` observed 32 stable closed samples, normal exit, retained two
shortcuts after restart and one new saved chord (total three). The running process
still reported granted after the setting toggle, and restart restored Collecting
without a traced manual entry, as PRD L3 requires for a persisted collecting
preference. Manual Start after this restart is not an acceptance gap. Explicit
denied permission remains unobserved. Both segments exited normally and are consumed.

Latest offline preparation distinguishes explicit denied/unknown permission
witnesses and fixes a failed-recovery settlement race that could lose retained
counts. The deterministic failing-first reproduction now passes, together with
the permission-priority case and all 63 product recovery/quit tests. All 590 package
cases pass. See [permission recording](PERMISSION_WITNESS_REPAIR_20260930.md) and
[recovery settlement](RECOVERY_SETTLEMENT_REPAIR_20260930.md). Historical
`inputMonitoringPreflightNotGranted` remains ambiguous. No new live round or
collecting Release qualification follows from these offline results.

Latest bounded modifier/UI result: unchanged signed Debug source `426969c9f`
received two explicitly coordinated left Command+A presses after an observed
Command-only release. It recorded shortcuts 2 / bare keys 0, ten accepted
handoffs and five successful durable writes. While Paused with the actual queue
closed, the owner confirmed expanded left Command 2 and TextEdit 2; normal early
Quit left no process. This supplies current-candidate bounded attribution and
modifier detail evidence, not broad keyboard/OS coverage, native accessibility,
restart readback or Release qualification. The earlier standalone-A round is
preserved under the owner's clarified interpretation.
See [exact chord round](CURRENT_COMMAND_CHORD_TRIAL_20260930.md).

The [2026-09-29 closeout checkpoint](MVP_CLOSEOUT_20260929.md) records fresh
offline results at `ba57ea711` and the reproducible arm64 trial build command.
The initial missing-profile error was resolved by one owner-approved Xcode
provisioning attempt: the arm64 trial at `de8b9c526` is signed and passed the
existing no-launch identity/profile check. An approved first-consent run completed
key provisioning and encrypted preferences initialization before Input Monitoring
denial stopped capture. No session or input was accepted. OS Quit and Reopen
showed a blocked state. A separately approved isolated restart reached Collecting
with granted Input Monitoring and one session, then quit normally at the
controller deadline. Keyboard callbacks, accepted events, aggregates and
flushes were all zero. This verifies bounded startup recovery, not physical
input or collected-count retention. A subsequent round, launched only after the
owner's explicit ready response, recorded 3 shortcuts, 0 bare keys and 4 issued/4
durable writes with no failure or timeout, then quit normally. This adds bounded
physical-input/save evidence. A separately approved restart read back 3 shortcuts
and 0 bare keys with zero input, writes or snapshot read failures, then quit
normally within its 20-second limit. Bounded aggregate restart readback is now
observed for this candidate; the broader live acceptance rows below stay open.

Current-main update: PR #13 merged at `6257b03b40f618fd976c6cbcc77dc83d374c59bb`. Marked Debug trials now reject missing isolation configuration on relaunch. The [bounded permission restart observation](PERMISSION_RECOVERY_TEST.md) preserves counts and normal Quit, but does not close same-process revoke/regrant coverage. PR #10 Secure Input evidence remains historical in [its report](PR10_SINGLEPAGE_REGRESSION.md); formal Phase 1 acceptance remains open.

Historical follow-up: PR5/6/7 were merged at `3b9345c30086e9e33c4510047e2692337f5b8643`. The subsequent paused-restoration repair completed its bounded owner-assisted rounds; see [the acceptance record and remaining scope](CURRENT_MAIN_ACCEPTANCE.md). The starting source and measurements below describe the earlier offline closeout, not fresh current-main qualification.

Starting source: `31b65c523db3ec40c06f0877395da52b7c026935` (merged PR #3/#4). Earlier roadmap audit reports 480 package tests and main CI 35643672591 successful at that source. Those are historical measurements, not a fresh run in this worktree. New measurements are recorded in the closeout report linked from current status.

| Requirement | Evidence / version | Gap | Safe autonomous work | Human / host prerequisite |
|---|---|---|---|---|
| FR-C normalization, sided modifiers, repeats, event origin | Package Core/Capture regressions; `426969c9f` recorded two coordinated shortcuts with zero bare keys and owner-confirmed left Command 2 / TextEdit 2; older candidate results remain dated | Broader keyboard/OS coverage; unknown first modifier side after reset is supported | Queue, normalization and synthetic provenance tests | The bounded current-candidate chord and row check above is complete; additional keyboard/OS cases require separately agreed input |
| FR-P privacy gate and zero metadata while closed | Synthetic privacy, overflow/generation, queued protection tests; bounded Secure Input closure/recovery on `64590a0e` ([report](PR10_SINGLEPAGE_REGRESSION.md)); older exclusion observation | Synthetic product permission revoke/explicit recovery is covered ([test](PERMISSION_RECOVERY_TEST.md)); actual OS permission delivery, broader continuous/hardware coverage and user switching remain open; one Debug Secure Input round is not full qualification | Inject false/unknown conditions with nonzero pending events; assert zero deltas and stale completions discarded | Separately approved short trials with coarse state/counters only, known permitted input before/after; no password text or per-event stream |
| Lock/sleep, user pause, recovery | Older signed Debug observed manual Start after lock and actual sleep | Not continuous locked-interval proof; current binary and OS support not qualified | Lifecycle/restart/flush race tests with delayed writes and synthetic lock providers | Owner operates lock/sleep; record closed state, retained durable counts, fresh-check recovery and paused-state behavior; no automatic unlock/wake |
| Encrypted persistence, missing key, corruption, reset/delete | Real temporary-file AES-GCM, crash subprocess, rotation/reset/recovery tests with injected keys | Real Keychain accessibility and current-candidate lifecycle qualification | Replay existing Store/Integration regressions, canary/serialization scans | Isolated explicitly approved test namespace and authorized controller; never remove user keys or use real statistics as fixtures |
| FR-P1 data stays on device | Product source scan and binary audit tooling have positive and negative fixture coverage; the latest recorded unsigned PR #17 Release executable from product source `e550075ca` passed the static audit ([privacy checks](PRIVACY_BOUNDARIES.md), [candidate record](PROJECT_STATUS.md)) | Repeat the source and binary audits on the exact final candidate. Prior packet observations remain invalid historical records | Use existing `PrivacyEgressTests` and `audit-product-network.sh`; review any future update checker separately | No packet-capture round is required |
| FR-S2 CPU / memory | Signed `a604ad535` Debug fixed-replay typing and idle each completed 30 s warmup + 120 s measurement, with durable replay totals, normal exits and within-budget host evaluation ([result](PERFORMANCE_SHORT_ROUND_20260929.md)); older observations remain separately dated | Agreed short native ARM measurement complete for this candidate; full product/Release and actual event-tap overhead remain outside this result. Intel belongs to later complete G1/v1 | Preserve raw samples and original invalid first window; only targeted anomalous/interrupted or performance-change reruns | No further owner action for this session; Release and deferred Intel qualification remain separate |
| Native UI / accessibility / consent / locales | Prior App XCTest and bounded screenshots at explicitly older revisions | Current-candidate manual flow, VoiceOver, appearance coverage | Build native Debug tests and universal Release; run only hostless tests known not to show windows while owner rests | Logged-in owner for UI/VoiceOver flow; window tests deferred while unattended |
| Release restrictions / distribution | Release uses BlockedLiveKeychain and UnqualifiedCapture | Release currently cannot collect; qualifying and connecting the real Keychain/capture path plus exact signed-binary audit remain necessary for an installable collecting MVP. Notarization is separately required for a public GitHub Release | Preserve the blocks until their real-path qualification; run source and exact final executable scans | Valid signing/provisioning for hosted tests; public release needs its own signing/notarization scope |

The local historical evidence remains read-only in the primary checkout under `.omo/repair-20260921/` and `.omo/repair-20260922/{modifier-investigation,roadmap-review}/`. Earlier live trials used a signed Debug candidate before merged main's diagnostic-path change. They are not current-main or Release qualification. See current status for the precise partial lock trial and durable-counter limitations.

The hosted Keychain Security adapter now uses the App's `LocalKeychainQueries`
source for exact-item add/read/attribute/delete queries. A compiled, effect-free
test verifies equivalence to the authorized probe request. Accessibility is set
on add and inspected afterward, not used to hide mismatched items from reads or
deletion. This is shared query execution preparation; it does not run the full
product backend or establish real Keychain lifecycle behavior.

The hosted Keychain scenario controller requires a separate product observation
for lock-transition results. Without it, those steps return BLOCKED; the fake
observer in offline tests establishes only that the controller handles supplied
measurements. `CounterWindowProductObserver` now supplies actual in-process
recorder deltas, exercised by the App's product-composition recovery test with
simulated host boundaries. An injected protected read is also rejected through
the hosted controller. No live product observer is wired into the signed probe
process yet. The adapter's closed endpoints and cumulative counters do not prove
that capture never reopened between samples or cover actual rendered pixels.
The Debug privacy journal records capture state, aggregate counters, protected
snapshot/analysis attempts, and successful snapshot/analysis assignments at the
flow boundary. These assignments do not prove screen rendering. Protected-data
reads outside those paths are still not counted exhaustively, and no product
observer is connected to the hosted controller. The journal cannot supply its
`protectedReadDelta` or `publishDelta`; absent values must not be projected as
zero. The hosted scenario report now leaves those deltas absent when no product
observation was made and blocks a lock-transition PASS if any required delta is
missing. Older journal lines without `analysisPublicationCount` yield an
inconclusive closed-interval evaluation. Finite interval samples also do not
prove that capture stayed closed at every instant of a lock.
The sleep/wake scenario now has separate `sleepClosed` and `wakeRevalidate`
steps. The previous composite step could accept one post-wake observation
without ever checking that capture closed during sleep. A failing-first offline
test reproduced that gap; the revised runner stops before wake when the sleep
closure observation or independent locked witness is missing. The old composite
step remains decodable but cannot pass. The complete offline package suite and
unsigned hosted Xcode test bundle build passed. This is scenario-model coverage
only: there is still no live lock authority or product observer attached to the
hosted test App.
Another failing-first regression found that a lock/unlock scenario could claim
PASS without a Keychain read during either transition. The hosted controller now
performs one signed-effect read of its exact test item after each lock, unlock,
sleep or wake witness and product observation. The runner rejects
a transition without that call; an unlocked read must succeed and match the
item. A locked read records the raw macOS status without assuming it must fail,
because the independent product lock gate remains authoritative. The hosted
controller blocks cross-device restore when no second device exists. A separate
failing-first regression showed that the in-process controller also labeled a
same-process witness as a successful restart. It now blocks both restart scenarios
until an external controller can prove a new process and a fresh product witness.
An equivalent reproduction showed logout/login could pass without any session
handoff; the hosted controller now blocks that step until a real session controller
exists. The offline KeychainLifecycle suites passed 40/40 and 82/82. The unsigned
hosted Xcode test bundle compiled. No real Keychain, lock transition, product
observer or process restart was exercised, so host lifecycle qualification remains open.
The hosted product-observation type now retains missing counters as absent
values. A missing capture-closed observation on a lock step now yields BLOCKED
instead of FAIL; an observed still-open capture remains FAIL. The missing-capture
test failed before this repair and passed afterward. Both offline
KeychainLifecycle test bundles passed 28/28 and 82/82, and the unsigned hosted
Xcode test bundle compiled. No product observer or real Keychain operation was
added by this classification repair.
The hosted controller now checks its authority preflight for every lock
transition and requests a fresh unlocked witness for the delete/missing read;
loss of that witness blocks the step before another Keychain operation. This is
offline controller behavior, not a qualified system lock observation.
The scenario report also rejects a claimed CRUD, delete/missing read, or cleanup
PASS when its recorded Keychain call count does not match the operations that
step must have executed; a zero-call fake cannot qualify those steps.
The hosted controller now reports the backend's actual per-step call-count
change even when a later operation throws. Before this repair, add followed by
an interrupted read yielded a blocked step claiming zero Keychain calls, while
the cleanup call was still counted. A failing reproduction and follow-up tests
cover interrupted CRUD, delete/missing read and cleanup. The full offline
KeychainLifecycle package test suite and unsigned hosted test compilation
passed. No real Keychain item or lock transition was exercised by this repair.
The probe's signed effect request and the current armed Debug product both select
the nonsynchronizable data-protection Keychain (`kSecUseDataProtectionKeychain`,
SDK key `nleg`) so that `WhenUnlockedThisDeviceOnly` can apply. The earlier Debug
product used the traditional file Keychain, where macOS does not apply that
accessibility attribute. An unavailable data-protection Keychain now blocks
product bootstrap without falling back. Query construction tests do not perform
real Keychain operations. A successful probe result still cannot establish that
the product's own backend closed or reopened correctly across lock transitions;
that requires an isolated product run with product observation.
An opt-in hosted XCTest now compiles a real, exact-namespace data-protection
Keychain add/read/attributes/delete/read-after-delete path. It requires an
explicit run switch and a valid signed host manifest whose only permitted
operation is Keychain. The test retains the exact service in the private
attempt directory for cleanup
if a later step fails. It has only built unsigned; no real Keychain operation
has run. It can establish isolated CRUD behavior, not product lock lifecycle.
An offline product regression models an existing encrypted store after its old
Keychain namespace becomes unavailable: relaunch stays out of Collecting, creates
no replacement key and leaves the encrypted manifest unchanged. It does not
establish real macOS Keychain access or migrate earlier trial data.
The collecting monitor now also reads the session-lock provider on each 250 ms
poll. A locked or unknown result revokes capture, closes protected state and
requires an explicit Start after an unlocked read. A hostless product test omits
the lock notification and checks both results, including no automatic recovery.
The interval is a polling cadence, not a guaranteed real-macOS closure time;
actual lock/sleep delivery and continuous closed-state evidence remain open.

The Debug distributed screen-lock callback now revokes the key gate, capture queue,
and manual recovery fence synchronously, before scheduling main-actor lifecycle
cleanup. A hostless product test failed on the previous implementation: directly
after a delivered lock notification, the gate and queue were still open and a
synthetic event was accepted. The same test now observes the gate and queue
closed and the event rejected before the callback returns. The unsigned Debug
App test bundle compiled; two logged runs of all 53 product recovery tests
passed. An earlier full run reported
three failures with its diagnostic lines lost to console truncation; the two
logged reruns did not reproduce them. This proves the local callback ordering,
not delivery timing or protected-state closure on a real macOS lock.

## Executable lanes and their meaning

- `Scripts/verify-local.sh --build-only`: package tests, offline harness CLI regressions, SwiftPM Release, universal unsigned App Release and native Debug test compilation. Does not launch capture or run App XCTest. A completed build is not Intel execution.
- `swift test --filter 'Phase1|Privacy|Keyring|CycleReset|Rotation|Flush|Lifecycle|Capture'`: focused synthetic regressions; use the full suite for final package coverage. Build directories are per checkout; do not run concurrent SwiftPM jobs in the same checkout.
- `swift test --filter PerformanceDriverTests`: short in-process synthetic queue → reducer → encrypted temporary store probe. It uses fixture keys, never Keychain or an event tap. Inspect both `PERFORMANCE_RECEIPT` and `PERFORMANCE_BUDGET`; a green XCTest only means the measurement/assertions ran, not that budget passed.
- `Scripts/audit-product-network.sh <Release Mach-O executable>`: static capability scan of the exact Release executable being qualified, with linked-socket negative fixture. Debug's main binary is only a loader; it cannot alone represent the Debug dylib. The result is a capability audit, not a measured zero-packet claim.
- `Scripts/phase1-qa.sh host <capture|sp6a|performance|signed-build> --manifest <approved-host.json> --attempt <fresh-absolute-repo-directory>`: active host qualification modes. The historical `network` mode remains registered but BLOCKED and is no longer a FR-P1 prerequisite. The shipped unavailable controllers deliberately return BLOCKED; a made-up manifest cannot grant authorization or make a controller exist.
- The revised `KeyRecordCaptureHarness --mode offline` exercises in-memory Core fixtures only. `--help` and no arguments show help; physical/synthetic modes now return BLOCKED before any host adapter is created. Run `bash Scripts/test-capture-harness-offline.sh <path-to-revised-binary>` for CLI regressions. Do not run that script against an older binary: the historical harness's `--help` started live capture and its `synthetic` mode posted OS events. The old live implementation lacked continuous privacy checks and has been retired; Git preserves it as historical evidence. This tool does not qualify the product pipeline.

## Performance plan

The owner revised the formal protocol on 2026-09-29: one typing window and one
idle window, each with 30 seconds warmup and 120 seconds measurement. This is
the formal default, not an exploratory shortcut before a mandatory hour-long run.
The two windows total 300 seconds, plus startup/consent, two-second drain tails
and normal exit. Longer endurance work is optional investigation, not a default
acceptance prerequisite. The dated six-window preparation below is historical.

1. Identify the build, native architecture, macOS and machine. Retain the existing loader/product-code identity checks and raw samples. Both windows must use the same candidate and host; each has an independent process/start time. Historical reports are retained under their original protocol, not silently requalified by the new evaluator.
2. Use the dedicated approved trial namespace/store and real local data-protection Keychain. The Debug fixed replay bypasses the system event tap, uses a fixed foreground and posts no input to other apps. It retains real permission, lock and Secure Input monitoring. This measures processing/storage/monitoring costs, not all real event-tap overhead or long-term stability. Wait up to 120 seconds for Collecting after owner readiness; replay 1,500 ticks over 150 seconds, followed by a two-second drain tail. Verify queue drain, expected accepted events and durable aggregate before accepting completion.
3. Run typing and idle once each on native Apple Silicon. The offline session evaluator reads exactly `typing-1` and `idle-1`, recomputes each raw archive and checks both phases; its result remains separate from product qualification. The old 3-repeat schedule is removed. Only an interruption, anomalous result or performance-related change justifies a targeted rerun; retain the first result and reason, and never select the best run or hide a failure in a median. Schedule while the owner is available; do not prevent sleep. A new live rerun requires approval. Intel remains later work, with the same shorter protocol when needed. The old shell host controller remains BLOCKED.
4. CPU = process CPU seconds / elapsed monotonic seconds × 100, relative to one logical core. Require an observed sample at or beyond the full 120-second endpoint; even a nearly complete shorter window is interrupted. Report each phase's mean CPU: typing <1%, idle <0.1%. Physical-footprint mean and sampled peak must each stay below 100 MB for both windows. Sampled peak does not establish a continuous maximum. Preserve sleep/session/PID/sample-integrity checks and exclude warmup; do not substitute RSS or whole-machine CPU.
5. Keep raw samples, durations and workload completion. Report observer/fixture overhead without arbitrary subtraction. Empty/missing/interrupted evidence is not PASS. The reduced duration does not weaken permission/consent, isolation, protected-state or normal-exit requirements.

Protocol-change verification: 35 focused package tests passed (6 host evaluator,
16 resource/interval evaluator, 11 receipt and 2 fixed replay), including exact
endpoint, budget thresholds, identity/process mismatch and rejection of legacy
formal duration. Debug build-for-testing and the hostless product replay/store
test passed. Two-window controller evaluation and synthetic-process sampler
self-checks passed; no product performance window ran. Local logs:
`/private/tmp/keyrecord-short-performance-{tests,controller-selfcheck,sampler-selfcheck,app-build,product-test}.log`.
The existing installed sleep-tested candidate has not been replaced; a fresh
matching performance build is needed before its separately approved host run.

Candidate review found that fixed replay had used a constant-granted Input
Monitoring stub, so a formal product replay would not include the real system
preflight cost. The App now supplies `SystemInputMonitoringPermission` to the
replay source. Replay requires authorization before Collecting and keeps the
same preflight in its collecting-state monitor; only hostless tests inject a
synthetic permission provider. Two focused replay tests, including denial, and
an unsigned Debug App test build passed. No host replay was run after this change.

The private native ARM Debug trial package prepared from this PR has bundle ID
`com.keyrecord.trial.performance5c54a178`, a distinct display name and the
required isolation marker. Its ad-hoc signature passed strict verification.
The loader digest is `9e4aa08ea71d55e2cc6e651ff59ec40152e9df848f141cf6d80aaaaf41d69480`;
the actual Debug code digest is `86babf978c04e9955cd1e5f9e3dfaf90f4756ead20dd178f3a3d354a7b88f559`.
The controller's `--check` accepted those exact files without launching the
App. The sampler and six-window evaluator passed synthetic self-checks only;
there are no product resource samples or Keychain effects from this preparation.

That first package predates the later candidate and its product-code digest does
not match. A second native ARM Debug package was built from source commit
`df6163f85896a7d906bc7c99b026b496e16328e1` at
`/private/tmp/keyrecord-performance-current-df6163f8/DerivedData/Build/Products/Debug/KeyRecordApp.app`.
It uses bundle ID `com.keyrecord.trial.performance.df6163f8`, the dedicated
Performance Trial display name, and the required isolation marker. Its ad-hoc
signature passed strict deep verification. The loader SHA-256 is
`63ebbad86770d099762db652f3157a59de72b223d026a964f991c6fc05276cd2`;
the actual Debug product-code SHA-256 is
`94245b8df2a0e6bbefe7ca7adee379bbe70052d0209560d2106af3948a1aae39`.
The controller's `--check` accepted this package and reported `launched=false`.
The current sampler's offline self-check reported `measured` with recomputation
and marker alignment matching; the six-window evaluator's synthetic self-check
also passed. No performance window, product Keychain operation, or qualification
measurement was performed with this package.

That earlier `--check` only verified the ad hoc code signature. The performance
replay subsequently needs the product's data-protection Keychain, and the
permission witness trial showed that a valid code signature alone can still
lead to Keychain status `-34018`. The controller now requires a matching
embedded provisioning profile and signed application identifier before it
reports a trial package ready. Rechecking the second package above returned
`trial-provisioning-profile-missing` with exit 2 and did not launch it. This
preflight prevents a known unusable package from consuming a formal window;
it does not prove that a future package can access the Keychain at runtime.

The subsequent cycle-reset repair at `648144555b0bee70b819148f381de1d6aacbb54c`
changed the product code again. An unsigned Debug build of that source has
`KeyRecordApp.debug.dylib` SHA-256
`4579f6a27b9df613190a7027f0c08d5a796750226f4f078439f3ea697893fd60`,
which differs from both prepared trial packages. They remain no-launch historical
preparations, not a measurement package for the revised source. Prepare a matching
isolated package only for an approved real performance session.

An offline resource-evaluator reproduction showed that a sampled clock or CPU
counter could decrease between samples while the window still reported
`measured`; a child-CPU counter decrease could also leave the
product-process-only result true. The evaluator now rejects nonfinite and
nonincreasing sample clocks, decreasing process or child CPU counters, and
nonfinite duration inputs. The reproduction failed before the repair, then
passed; all 16 focused resource/host-evaluation tests and both sampler and
six-window synthetic self-checks passed. This validates arithmetic rejection
paths, not ARM or Intel product resource budgets.

## Minimum owner-assisted follow-up

Before asking the owner to act, prepare the exact signed candidate and a bounded run plan: candidate/version, private output directory, permitted store/key namespace, steps, normal shutdown and forced-stop fallback. Obtain approval for the particular session/privacy/Keychain operations. Existing build permission does not cover them.

For a newly justified live round, rather than automatically repeating prior evidence, start with one 30–60 second current-candidate count → pause/resume → normal quit/restart trial using only agreed shortcuts. Record starting/ending aggregate totals and successful durable completion, without real text or event sequences. Then schedule separate exclusion/foreground and lock/sleep trials; do not compress permission changes, user switching and Keychain failures into one opaque run. Exclusion trials must record and restore the original switch state. Lock/sleep recovery uses explicit menu **Start** and fresh checks; do not promise automatic resume or a one-second loss limit.

Continuous boundary evidence needs a privacy-safe observation mechanism before the owner is asked to reproduce it. Coarse state transitions and numeric aggregate/durable counters may be retained; keystroke timestamps, text and raw sequences may not. Screenshots at the endpoints alone do not establish zero capture throughout a closed interval. Fast-user-switch, permission and test-Keychain trials require their own approved setup; native Intel and public release remain later independent work, not Apple Silicon MVP prerequisites.

The current Debug privacy journal can also record `protectedGateEntries`, a cumulative count of operations admitted by `KeyAvailabilityGate` through its synchronous and asynchronous guarded entry points. A locked or stale attempt does not increment it. The value is absent when the recorder is not wired to the gate or the count overflows. This is a conservative diagnostic for paths using that gate; it does not establish that every protected read uses it or that a closed interval stayed closed between journal samples. No live lock or Keychain qualification is claimed from this offline instrumentation.
The closed-interval evaluator now treats a missing gate count as inconclusive, a decrease as invalid, and an increase between the close and reauthorization boundaries as an observed gate admission during closure. Earlier journals without this field remain usable for other observations but cannot satisfy this check.

An offline race test exposed a separate store lifecycle fault: `ObjectStore.bootstrap()` could suspend on key inventory, receive `closeProtectedSession()`, then resume and set the store phase to `freshInstall`. Git revisions, file versions, types and ordinary sequential tests cannot order an asynchronous continuation against a same-process close; the reproducer exercised that ordering directly. The store now invalidates the suspended bootstrap's session token on close and checks it after asynchronous key and journal work before publishing an opened phase or reconciling owned files. Product startup, load and save also run their asynchronous store steps under the current key-gate generation. The reproduction failed before the repair and passed afterward; a second test covers closure while the manifest key is pending. All 165 Store tests and 51 hostless product recovery tests passed, including save after a deliberate session close. These results establish the offline race repair, not real macOS lock or Keychain accessibility behavior.

A follow-up reproduction found the same ordering fault during first-installation manifest creation: a pending key request returned after session close and still committed `manifest.krenc`. Initial creation and the raw store read/write/delete paths now check the same session token after key retrieval, before plaintext return or file mutation; a late key result cannot repopulate the transient cache. The initial-creation reproduction failed before the repair and passed afterward. The five session-closure tests, all 168 Store tests, 51 hostless product recovery tests, and unsigned Debug App build passed for this follow-up candidate. These are offline results; no real Keychain or lock session was exercised.

A further failing-first reproduction paused cycle reset during Keychain version
inventory, closed the protected store session, reopened it, then released the old
inventory call. Before repair, that old reset completed and changed the current
cycle in the new session. Cycle reset and pending-journal continuation now retain
the original protected-session token across their asynchronous steps and check it
before further writes. Both closed-session regressions and all 170 Store tests
passed; the unsigned arm64 Debug App built and 53 hostless product recovery tests
passed. The first product XCTest attempt used incompatible DerivedData and failed
before running tests; the fresh test build produced the 53-test passing result.
This is an offline race repair, not a real lock or Keychain qualification.

Candidate review found a further asynchronous rotation boundary. A pending
Keychain read could return after the protected store session closed and let the
old migration create a ciphertext locator or replace the manifest. Two
deterministic regressions failed before repair and passed afterward.
Protected-reference sessions now retain the store session token across migration,
manifest reencryption, recovery and scans. Rotation checks the token and the
existing key gate after awaited key reads and before further file writes. A
separate test rejects a reference session reused after close and reopen. The
Store suite passed 172 tests before that last test was added; the last test
passed separately, and the SwiftPM Release build succeeded. These are offline
results, not a real lock or Keychain qualification.

For source commit `4a264da3b`, `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed 6/6, including the network-linked negative fixture. A fresh unsigned Release App built with arm64 and x86_64 slices; its only executable passed `Scripts/audit-product-network.sh`: SHA-256 `84e37ba693dff4ce3b4bd6c9b9f6759445440e83a22263aaedc5340ebbc0666d`, 1,854 undefined-symbol lines, 20,192 string lines, zero matches, `liveReceipt=false`. `codesign` reports an ad hoc linker signature without a Team ID. This is static evidence for that exact local executable. The final signed Release artifact remains unaudited.

For source commit `888438edddad74d5779d28a6b40be203174391a6`, `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed 6/6. An unsigned Release App build with `ARCHS="arm64 x86_64"` and `ONLY_ACTIVE_ARCH=NO` succeeded; `lipo -archs` confirmed both slices in the executable. `Scripts/audit-product-network.sh` passed on that exact executable: SHA-256 `8aa1be8f9a0cacc9e8f8890287f2133f40e65d76e9ca36f3868d8f424113fcf1`, 1,854 undefined-symbol lines, 20,132 string lines, zero matches, `liveReceipt=false`. This is static evidence for the specified unsigned candidate only. The final signed Release artifact has not been built or audited, and no live network observation is claimed.

For source commit `69e34284ea6af1f69f25e45a6f81933d68af5c66`, the same six privacy source and negative-fixture tests passed. Its unsigned universal Release App built successfully with arm64 and x86_64 slices. The exact executable passed `Scripts/audit-product-network.sh`: SHA-256 `89d44bbffd29c12707fba8f5bd35a88f962ca198e314793af9550615cd28d72b`, 1,854 undefined-symbol lines, 20,127 string lines, zero matches, `liveReceipt=false`. This was the next unsigned candidate; the signed Release artifact remained unaudited.

For earlier PR source commit `2095183e5dca3105f396984908a4da9e5fd9d7fb`, all six `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed, including the linked-socket negative fixture. A fresh Release App built with arm64 and x86_64 slices and no Developer ID signature; `codesign` reports only an ad-hoc linker signature with no Team ID. Its sole bundled executable passed `Scripts/audit-product-network.sh`: SHA-256 `2a8678a681f139bdfa7c27590ab0974eab00169088a8b76939a2d86ef2e4a48c`, 1,854 undefined-symbol lines, 20,127 string lines, zero matches, `liveReceipt=false`. This is static evidence for that exact local executable. The final Developer ID signed Release artifact has not been built or audited.

For product source commit `648144555b0bee70b819148f381de1d6aacbb54c` (the following `14c1eb1d` commit changed documentation only), all six `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed, including the linked-socket negative fixture. A fresh unsigned Release App built with arm64 and x86_64 slices. `codesign` reports only an ad-hoc linker signature with no Team ID, and the App contains one bundled executable with no Debug dylib. That exact executable passed `Scripts/audit-product-network.sh`: SHA-256 `3df2deb909f04a576c8270ad8abe95171f2d9cbffa4a44dc1b732fd22b383a08`, 1,854 undefined-symbol lines, 20,176 string lines, zero matches, `liveReceipt=false`. This is static evidence for the local unsigned executable; the final signed Release artifact has not been built or audited. No live network observation was performed.
