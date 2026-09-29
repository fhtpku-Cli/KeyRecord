# Current project status

## Current Apple Silicon MVP status — 2026-09-29

Latest autonomous checkpoint: [MVP closeout](MVP_CLOSEOUT_20260929.md).
The latest offline increment adds DEBUG preparation boundaries and the existing
cumulative `sessionCount` to the opt-in privacy journal. This helps locate future
capture resets around aggregate increments without persisting event traces.
The count records preparation attempts before activation, not proven tap starts.
The failing-first boundary regression now passes, along with 71 focused cases and
60 product recovery/quit cases. The 590-case package run found one missing privacy
inventory registration; after registering only the new integer field, all 46
integration cases pass. The other 544 cases passed in the full run. Debug/unsigned
arm64 Release builds and the zero-match static audit pass. The installed trial
and historical side-unknown evidence are unchanged. See the
[completion plan](PHASE1_COMPLETION_PLAN_20260929.md#observe-capture-preparation-boundaries--2026-09-30).
Latest owner-assisted paused readback now has an expanded screenshot: two ordinary
Command+A uses and TextEdit attribution are visible, but exact Command side is
unknown. Normal Quit completed with no new callbacks, counts or writes; exact PID
21499 is gone. An offline queue-to-product-to-analysis test preserves known sides,
so no speculative capture change was made. The original input round's eight
session preparation attempts do not locate a reset between presses; the cause remains unresolved.
The screenshot's contradictory bare-key empty message is corrected in both
languages. See [current UI evidence](CURRENT_UI_TRIAL_20260930.md#manual-provenance-readback-completed).
This adds bounded rendering evidence, not accessibility or Release qualification.
Latest offline repair also binds each keychain deletion plan to its inventory's
original generation, preventing lock/reopen from reauthorizing stale work. Overlapping
adapter operations are rejected and failed finish releases the plan for a fresh
explicit retry. All 33 focused deletion/recovery tests and all 589 root-package
tests pass. Unsigned arm64 Release and its zero-match static network audit pass.
The preceding stage-fencing repair remains in place. No live deletion or installed
trial replacement occurred. Atomic cancellation of admitted operations and system
lock qualification of the full filesystem/login sequence are not claimed.
Details: [completion plan](PHASE1_COMPLETION_PLAN_20260929.md).
Debug diagnostics now also read actual queue admission and key-gate state, rather
than relying on the delayed lifecycle live flag. A failing-first product test
reproduced the missing observation; both targeted product tests and all 43 focused
package tests pass. Debug/unsigned arm64 Release builds and the existing static
network audit pass, with observation code absent from Release. These are sampled
product states; the real hosted observer and independent lock authority remain
unimplemented. Native current-candidate row/status inspection is the next bounded
owner-assisted acceptance step; completed performance/sleep evidence is retained.
The owner-approved/readied signed `346dc26d8`
[bounded native UI/attribution round](CURRENT_UI_TRIAL_20260930.md) recorded two
physical shortcuts, aggregate delta/totals two and six successful durable writes.
Pause closed the actual queue; normal Quit completed and the exact PID is gone.
Computer Use disconnected before returning a native view, so rows, application
attribution, rendering and accessibility remain unverified. The round's occupied
private directory is preserved; no automatic repeat is authorized.
Subsequent pure AppKit regular/accessory control windows both returned native
accessibility trees. The observation service is usable for these minimal targets;
accessory shape alone does not reproduce the product failure. The exact product
hierarchy/helper trigger remains unresolved; no live trial was repeated.
The separately approved/readied paused UI readback completed on the same candidate:
two shortcuts restored, zero new callbacks/handoffs/aggregate delta/writes or read
failures, all five journal records closed, and normal Quit with exact PID gone.
The owner opened the aggregate tab, but native observation again disconnected.
The owner reported two occurrences and subsequently explicitly confirmed seeing
TextEdit. Exact left/right modifier provenance remains unconfirmed. This is bounded
readback and owner-observed attribution evidence, not full UI/accessibility
acceptance or a repaired helper. Readback output names are consumed; no auto-relaunch.
The 2026-09-30 increment retains Debug read/processing counts at synchronous
key revocation, before queued cleanup writes the journal. A failing-first product
test reproduced the missing observation; the repaired evaluator detects activity
in that gap and treats missing evidence as inconclusive. All 47 focused package
tests and all 59 product recovery tests pass. Debug and unsigned
arm64 Release builds pass, and Release excludes this observation with zero static
network audit matches. Full hosted observation and an independent OS lock witness
remain open. This is offline evidence; the installed signed trial is unchanged.
Latest observation increment counts plaintext-processing scopes through parsing,
validation, serialization and key/crypto operations, including in-flight work.
The evaluator preserves historical coverage limits and rejects missing groups.
The 570-case package run and 80 selected product tests pass; after the last
crypto-coverage extension, all 221 affected cases and two product boundary tests
pass. Final Debug/unsigned arm64 Release builds pass; Release excludes Debug
observation state and its static network audit has zero matches. Full hosted
observation remains open; the next increment above addresses the journal's start
against immediate key revocation. No new live evidence is claimed.
Latest product regression reproduced cached aggregate/analysis visibility and
publication after synchronous key revocation but before lifecycle state updated.
Product flow now uses the existing key gate for presentation access and retains
the producing generation; reopening alone cannot expose an old presentation.
All 89 selected hostless product tests pass, with Debug and unsigned arm64 Release
builds and the zero-match static network audit passing. This covers model reads
and publication, not rendered pixels or complete hosted observation. No live run
occurred. Details and failing-first evidence are in the completion plan.
Latest safety repair serializes aggregates under the existing protection scope and
carries the producing generation into scheduler staging, preventing old batches
from entering a reopened session. Preference coding after awaits is also fenced.
All 201 affected package tests, 11 reduction and 57 recovery/quit tests pass; Debug
and unsigned arm64 Release builds pass, with zero static network audit matches.
The installed signed trial remains unchanged and no new live round was run.
Latest offline increment adds Debug process-wide actual decrypt/Keychain, cached
store and in-memory aggregate read start/completion counts to the privacy journal.
The product-path closure test verifies all eight counts stay balanced and unchanged
through explicit reauthorization. All 57 recovery/quit and 10 reduction tests pass.
The 564-case package run found one source-length failure; helper extraction fixed
it and all 175 affected storage tests then passed. Debug and unsigned arm64 Release
builds succeed; Release excludes the observer and its static network audit has zero
matches. Plaintext processing, publication and full hosted observation remain open;
this is not new live acceptance. Details are in the completion plan below.
The owner has set an active goal to complete Apple Silicon Phase 1, continuing
autonomously until a concrete host step needs cooperation. The
[completion plan](PHASE1_COMPLETION_PLAN_20260929.md) records the remaining work.
An encrypted-store regression reproduced active-day encounter order being lost
across restart after date rollback. The repair persists encrypted daily order
and removes it during cycle reset; 52 focused tests and all 553 SwiftPM XCTest
cases pass. The App test build and all 69 selected hostless product recovery,
reduction and startup cases pass. Earlier live evidence retains its original
candidate bounds.
Product Keychain queries now explicitly forbid authentication UI; all seven
hostless query tests pass after reproducing the omitted-policy failure.
Signed candidate `293f25a45` includes both repairs and passes build/profile/isolation
checks. Its owner-approved/readied fresh isolated input/save/restart-readback check
now completes: one physical key-down and one key-up, aggregate delta one, four
successful durable writes, then the same shortcut total one after restart with no
new input, writes or read failures. Both launches quit normally with no remaining
App process. The MVP trial is updated with the old bundle preserved; the Performance
Trial is unchanged. Both CI builds at `e808d6483` pass. See the completion plan for
artifacts and limits. A subsequent separately readied permission-toggle round
observed fail-closed capture/hidden state with 19 unchanged closed samples, then
normal Quit. After the owner restored permission and confirmed readiness, an
isolated restart freshly observed granted permission and saved one further
shortcut (total two), with two successful durable writes and normal Quit.
Both exact App processes are gone. The closure trigger was `tapUnavailable`,
without a denied-permission witness, so this remains bounded toggle/closure and
restart recovery evidence, not full permission qualification. Full hosted
observation and collecting Release qualification remain open. A failing-first
hostless regression reproduced the diagnostic gap when an unavailable tap closes
the product before permission changes. Debug closed-interval observation now
records noninteractive granted/not-granted preflight witnesses, without reopening
capture. All 57 recovery/quit and 16 interval-evaluation tests pass; Debug test
build succeeds. The installed `293f25a45` trial and its host evidence are unchanged.
Formal performance acceptance was shortened at the owner's request: typing and
idle once each, 30 seconds warmup plus 120 seconds measurement per window,
about five minutes plus startup/exit. Targeted reruns replace automatic repeats;
budgets and privacy/integrity checks are unchanged. This changes the formal
default, not merely an exploratory precheck. See [the protocol](PHASE1_ACCEPTANCE.md#performance-plan).
The approved replacement typing and idle windows now complete on signed
`a604ad535` with controller `1cf51a056`. Both report measured, completed replay,
normal exit and no failed checks. Host evaluation is within-budget: typing CPU
0.0983%, idle CPU 0.0807%, highest footprint mean/peak 33.93/34.06 MB. Typing
saved 2,550 key downs in 145 successful durable writes; idle accepted zero events.
No product process remains. This closes the agreed short native ARM measurement,
not full MVP/Release or real event-tap overhead qualification (productPass=false).
The first invalid window and its reproduced post-exit architecture query bug
remain separately recorded; the repaired controller captures architecture while alive.
The [dedicated performance package preparation](PERFORMANCE_SHORT_ROUND_20260929.md)
compiled successfully on `a604ad535`. Its initial missing-profile blocker was
resolved by one owner-approved Xcode attempt (33.3 seconds, exit 0). The signed
Performance Trial is installed separately; signature/profile/isolation checks
passed before launch. The owner enabled Input Monitoring and confirmed Collecting
separately for the completed replacement windows. See the linked round record.
The completed [second sleep/wake round](SLEEP_WAKE_SECOND_ROUND_20260929.md) on
signed `cf08a07c` observed 32.028 seconds suspended, sampled closure through wake
with unchanged counters, explicit Start back to Collecting, new post-recovery
input and successful save. Normal early Quit at 223.431 seconds left no process.
Final totals are 12 shortcuts/2 bare keys, with 12 successful durable writes and
zero write/read failures. The repaired interval evaluator reports observed.
This completes the narrow collecting sleep/wake/manual recovery/input/save
scenario, not continuous privacy or full hosted lifecycle qualification. The
[first partial round](SLEEP_WAKE_ROUND_20260929.md), which ended before final
input, remains separately recorded and unchanged.
The [collecting lock and explicit recovery round](NEXT_HOST_ROUND_20260929.md)
has now completed on signed `8e3ca0c55`: locked and unlocked-before-Start
observations stayed closed with unchanged counters; explicit Start restored
collection and saved new input; normal Quit left no process. The old interval
end marker also included 20 gate admissions during authorized Start recovery,
so the unmodified evaluator reported `closed-interval-protected-gate-entry`.
An offline-reproduced Debug journal repair places the end before explicit
unlocked store reauthorization. All 55 recovery/quit and 15 interval evaluation
tests pass; this newer diagnostic repair is installed in signed `cf08a07c` and
now has the separate sleep/wake observation above.
The new focused hostless sleep recovery test passed, as did signed build and
installed-package checks before that live round. The original lock journal and its
evaluator result remain unchanged. See the
candidate-specific [lock result](PERMISSION_RECOVERY_TEST.md#bounded-collecting-lock-and-explicit-recovery--2026-09-29).
Both CI jobs for diagnostic repair `1e3918136` passed; performance-tool
self-checks remain synthetic, with no new product resource window.
The follow-up signed repair `8e3ca0c55` now has a separately approved bounded
host result: Collecting survived the owner's TextEdit input and return to chat,
with three capture sessions, no false Blocked phase, four successful durable
writes and normal Quit at 55 seconds. No process remained. The 17-record journal
contains only Collecting then Stopped. Shortcut total moved 4 to 7; the owner
confirmed one Command-A, but aggregate-only evidence cannot identify the other
two shortcut increments. This closes the narrow regrant/isolated-restart and
foreground-rebuild regression round, not same-process revocation or the full
privacy/Release requirements below. No further owner action is needed for this
round.

The subsequent reason-classification repair replaces the generic handler's
incorrect `sessionLocked` label with `privacyCheckRequired`, while retaining
actual lock reasons and all closure protections. Three new assertions failed
before the repair; all 53 recovery/quit and 233 Core tests passed afterward.
The owner clarified the last system prompt was Quit and Reopen. On signed
`10676e1aa`, re-enabling the exact trial followed by an isolated restart reached
Collecting; one confirmed shortcut increased the restored total from 3 to 4
with one successful durable write. Normal Quit left no process. An unexpected
`sourceStopped` block before Quit prevents a sustained-recovery pass. A held
foreground rebuild reproduces that false block offline; the follow-up repair
keeps health observations during reconciliation from becoming permanent faults
while retaining the permission/lock checks. See the candidate-specific record
and the passing 55 recovery/quit tests (zero failures; Debug test build passed)
in [permission recovery](PERMISSION_RECOVERY_TEST.md). The older results below
remain bound to `de8b9c526`.

At `ba57ea711`, 546 package tests, 133 selected hostless App tests and 122
KeychainLifecycle logic tests passed; fresh unsigned builds and the Release
network-capability audit also passed. An initial signing build identified a
missing provisioning profile. In one subsequently approved Xcode attempt,
the existing account generated the matching Mac App Development profile and
built the arm64 trial at `de8b9c526`. Its separately approved first-consent run
completed key provisioning and encrypted preferences initialization, then failed
capture startup with Input Monitoring denied. It never entered Collecting and
quit normally. The owner enabled Input Monitoring and used OS Quit and Reopen;
the reopened App was blocked and wrote no new isolated journal. A separately
approved restart through the explicit isolation controller reused that store
and namespace, reached Collecting with Input Monitoring granted, and quit
normally after the controller's 55-second request, before its 60-second limit.
It recorded one capture session but zero keyboard callbacks, accepted events,
aggregates and flushes because the coordinated input step was not completed.
After an explicit ready response, a separately coordinated input round recorded
3 shortcuts, 0 bare keys, 3 key-down/3 key-up/6 modifier callbacks and 4 issued/4
durable writes, with no write failure or timeout. It quit normally after the
55-second controller request and left no process. Local provisioning, initial
protected-store creation, isolated startup recovery and bounded physical input
through durable save now have product evidence. A separately approved restart
read back the same 3 shortcuts and 0 bare keys with zero new input, writes or
snapshot read failures. It quit normally after a 15-second request, within the
20-second limit, and left no process. This closes bounded aggregate restart
readback for this candidate; full Keychain lifecycle remains open. A reusable
trial build helper preserves the ordinary project defaults.

A later separately approved permission round observed Collecting followed by
Blocked with `privacyTrigger=sourceStopped`, `blockedReason=sessionLocked`, no
live capture session and hidden sensitive state. The owner reported a restart
or authentication prompt, triggering the agreed early stop. Normal Quit
completed and no process remained. The observed protected-state counters stayed
unchanged after closure, but all recorded Input Monitoring preflights before
closure were granted. The initiating cause is not isolated; no explicit
regrant/Start or recovery interval was exercised. This is partial closure
evidence, not permission-recovery acceptance. The final Settings toggle state
was not independently verified or automatically changed.

The owner accepts an Apple Silicon-only first usable capture MVP. Intel runtime,
Intel product-performance measurement and SP6B Intel backup-KDF timing are not
MVP prerequisites. The original full G1/v1 requirements still exist as later
work; neither G1 nor public Release is marked PASS by this scope decision.

The earlier PR #17 checkpoint assessed product source `87a26a216` on
`codex/phase1-acceptance`. The newer `de8b9c526` trial above has its own record;
later documentation-only commits do not rebind either candidate's host results.
Offline permission, tap-liveness, lock-callback and protected-store race repairs
are present. The provisioned trial above has bounded capture/save/restart
readback evidence. An earlier installed permission-witness trial appeared in
Input Monitoring, then failed before Collecting with effective data-protection
Keychain error `-34018`. A later isolated arm64 Debug App compiled from this
branch is ad hoc signed with no matching embedded provisioning profile; its
no-launch preflight rejected it. These packages cannot qualify revocation,
regrant, lock, sleep or product Keychain behavior. Do not repeat host toggles
with either package. See [permission evidence](PERMISSION_RECOVERY_TEST.md) and
[remaining acceptance](PHASE1_ACCEPTANCE.md).

The provisioned isolated Apple Silicon candidate now reaches Collecting through
its explicit wrapper and has retained the agreed small shortcut total across
restart. Bounded collecting lock and sleep/manual recovery now have the scoped
observations above. Actual permission revoke/regrant, continuous lock/sleep
protection remain open. The agreed short native Apple Silicon fixed-replay
typing/idle measurement is complete for `a604ad535`, as recorded above. Offline
KeychainLifecycle scenario tests have passed, but no live product observer is
wired into the hosted controller; its missing closed-interval counters cannot
count as zero. Current Release composition still uses `BlockedLiveKeychain` and
`UnqualifiedCapture`, so it cannot yet serve as a collecting MVP. The exact
eventual signed Release executable must pass the static FR-P1 capability audit;
earlier unsigned binaries passing that audit do not qualify it. Current-candidate
native consent/status/accessibility checks are also outstanding. No additional
host packet-capture round is required for FR-P1.

## 2026-09-28 network and permission checkpoint (historical)

Main includes PR #16 at `f7dbe7434188edb706e877f168ff9940f7bea438`.
The owner ended packet-capture qualification for FR-P1. This milestone has no
network client or update endpoint. The revised [FR-P1 requirement](PRD.md#66-功能需求隐私)
uses the product-source scan and an audit of the exact Release executable being
qualified, with negative fixtures for network, endpoint and shell references.
A future update checker needs a separate request-scope review; statistics must
stay local. No further host packet capture is needed for FR-P1.

Five owner-approved product observations on the closed PR #15 branch were
invalid. They provide no measured zero-egress result and remain in that PR's
commit history. The earlier synthetic loopback pilots in the
[observation record](NETWORK_OBSERVATION_PREP.md) only verified observer controls. These
results do not block the revised code-and-build capability assessment. The
historical `host network` lane remains inert and BLOCKED; it is no longer an
FR-P1 prerequisite. Signed Release, other G1 conditions, formal performance
and native Intel qualification remain open.

This closeout branch passed six focused `PrivacyEgressTests` and
`PrivacyBinaryAuditTests`, including negative fixtures. An unsigned universal
Release App built offline; its executable passed `audit-product-network.sh`
with zero matches. `EvidenceValidator` compiled. The eventual signed Release
candidate still needs its own audit before FR-P1 release acceptance.

## Phase 1 permission polling candidate — 2026-09-28

The `codex/phase1-acceptance` candidate checks Input Monitoring authorization in
the existing collecting-state monitor. A failed read revokes the capture queue,
closes protected state and leaves recovery to an explicit Start, including when
macOS does not deliver a tap invalidation callback. The synthetic product test
passes without sending such a callback. The 46 product recovery tests, seven
Capture permission tests and six Keyring lock tests passed. The 22 Release
isolation tests had zero failures and one skipped binary-dependent test;
that test was separately run
against this candidate's unsigned universal Release build and passed. That
build's executable passed the static network audit with zero matches. These
results establish offline behavior only. Actual macOS permission revocation and
regrant, real Keychain access, lock timing, formal ARM/Intel resource measurement
and signed Release qualification remain open.

Candidate review reproduced a late-write fault in protected Keychain rotation:
closing the store during a pending key read allowed an old migration to create a
ciphertext locator or replace the manifest afterward. The existing protected
session token now fences the reference session and resumed store work. Both
failing-first regressions pass after repair; the Store suite and a SwiftPM
Release build passed. This is an offline fix, not a host lock result.

The resource sampler's own synthetic self-check initially returned
`interrupted/duration-short`: its last sample landed 0.066 seconds beyond the
nominal endpoint and was discarded. The measurement evaluator now includes the
first sample at or after the endpoint when it is within 1.5 sampling intervals;
missing, excessively late and genuinely short windows still fail. The ten
resource-evaluation tests and two sampler self-check runs passed after this fix.
This repairs the measurement tool, not the missing product workload or formal
ARM/Intel measurements.
The later archive follow-up uses that same accepted endpoint when reporting
`effectiveMeasureSeconds`; previously, an accepted sample just beyond the
window could still make the archive report a shorter duration. Ten focused
resource tests and the sampler's synthetic self-check passed after this change.
The sampler CLI now rejects non-finite, zero and sub-0.1-second intervals before
sampling a process. Six malformed interval invocations exited promptly without
writing measurement archives; the valid synthetic self-check still passed.

The current PR candidate adds a Debug-only fixed replay source to the product
composition. A hostless product test drives a fixture tick through reduction
and encrypted persistence; a separate test checks that the replay fixture
matches the compressed measurement receipt's workload. The app-side replay
waits for Collecting and writes only aggregate progress to the trial's private
root. It has not been launched or measured on a host, so neither ARM nor Intel
performance qualification is established.

Review found that fixed replay had used a constant-granted Input Monitoring
stub, omitting the real system preflight cost from a formal product measurement.
The App now supplies the system permission provider; hostless tests inject a
provider and verify that denial blocks replay. Both focused replay tests and
an unsigned Debug App test build passed. The changed host path remains unrun.

Historical tool preparation under the former long protocol added a monotonic start marker shared with the
resource sampler and a two-second drain tail after the 60-second warmup and
600-second measurement window. Before reading the isolated encrypted aggregate,
the Debug product waits for its queue to drain and checks the reduced total
against accepted replay events. It then flushes and reads the aggregate back. The
one-window `KeyRecordPerformanceTrial` controller compiles and the sampler's
marker self-check runs against its own short synthetic process. Its offline
six-window evaluator verifies same-host/same-candidate identity and six distinct
process launches, recomputes the saved samples and applies the per-host budget.
Its file-loading path then passed an explicitly synthetic six-window self-check, but
has no real reports to evaluate. The controller has not launched a product App, and no ARM/Intel host
performance result exists. The formal host performance lane remains inert.

The 2026-09-29 owner-requested protocol update supersedes that default with two
30/120-second windows. The current two-window evaluator and sampler self-checks,
35 focused package tests, Debug build-for-testing and one hostless product
replay/store test passed. No real performance App was launched. The installed
sleep-tested `cf08a07c` App predates this replay-duration change and is not the
new performance measurement package.
The performance controller now rejects a trial package without a matching
provisioning profile and signed Keychain application identifier. Its previous
ad hoc package returned `trial-provisioning-profile-missing` in a no-launch
check. A passing profile check would still require a bounded runtime Keychain
readiness check before any formal measurement.

The standalone Keychain lifecycle probe built unsigned on native ARM and its
80 SwiftPM logic tests passed on this candidate. The build and tests did not
launch the probe, access the real Keychain, or operate the session lock.
Hosted Keychain accessibility and lock/unlock behavior therefore remain open.
At the later `codex/phase1-acceptance` head, 80 preflight tests and 17 hosted
scenario tests passed offline. The hosted controller no longer turns an assumed
zero product delta or capture-closed state into a passing lock result: without a
product observation it returns BLOCKED. A failed Keychain add stops the CRUD sequence
and records the failing status rather than allowing a later read to mask it.
These changes improve evidence integrity; no real Keychain or lock transition
was exercised.
The standalone probe and the current armed Debug product request the
nonsynchronizable data-protection Keychain. The earlier Debug product used the
traditional file Keychain, which did not enforce its requested
`WhenUnlockedThisDeviceOnly` attribute. The product now fails closed if the
data-protection Keychain is unavailable. The probe still has no live product
observer, so even a future probe result alone cannot qualify the product's
Keychain and lock lifecycle. The remaining evidence gap is recorded in
[Phase 1 acceptance](PHASE1_ACCEPTANCE.md).
The offline sleep/wake scenario now checks sleep closure and post-wake
revalidation as separate steps. Its previous one-step form could skip the
sleep interval; the failing-first test caught that model gap. A missing locked
witness also blocks before wake. The complete KeychainLifecycle SwiftPM suite
and unsigned hosted Xcode test bundle build passed after the repair. No sleep
or wake was performed on the host, and live lifecycle qualification remains
open.
Apple documents that macOS applies `kSecAttrAccessible` only when
`kSecUseDataProtectionKeychain` or `kSecAttrSynchronizable` is true
([attribute reference](https://developer.apple.com/documentation/security/ksecattraccessible),
[Mac Keychain technote](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
The revised Debug product uses the former and keeps synchronization false.
Its six query tests and the synthetic unavailable-Keychain product test passed;
the focused App run passed 76 tests with one Release-binary-dependent skip.
No real Keychain item was created or read in that run, and no lock transition
was performed.

The first owner-assisted same-process permission trial on the isolated Debug
candidate did **not** show the required closure: after Input Monitoring was
turned off for the trial bundle, the App still displayed Collecting. Its
private coarse journal has no permission-revoked or Blocked transition before
normal Quit. See [the scoped evidence](PERMISSION_RECOVERY_TEST.md#owner-assisted-real-permission-trial--2026-09-28).
The synthetic polling result must not be promoted to live permission acceptance.
An opt-in Debug witness now records whether the collecting monitor continues
to sample Input Monitoring. Its owner-assisted run recorded 14 granted samples
while Collecting, no non-granted sample or Blocked transition, and a normal
Quit. The owner's System Settings screenshot has no entry for this new bundle;
the only trial entry is the earlier bundle, with its switch off. The new bundle
was not revoked in this run, so these samples describe baseline polling only.
A narrow system-log review attributes the new bundle's permission request to
Terminal and shows a LaunchServices lookup failure at the time. A reusable
signed-trial launcher now uses LaunchServices and passed no-launch preflight,
but has not been run or verified in Settings.
The live acceptance remains open.
See [the witness trial](PERMISSION_RECOVERY_TEST.md#owner-assisted-permission-witness-trial--2026-09-28).

A later installed witness package did appear in Input Monitoring as
`KeyRecord Permission Witness Trial 20260928b`. Enabling it required Quit and
Reopen. Its initial isolated run failed before Collecting with unavailable
protected storage; `secd` ignored the embedded application identifier because
of an invalid signature or incorrect provisioning profile and returned
`-34018` on Keychain lookup. The automatic relaunch did not write to the
isolated journal. This is a trial-packaging failure, not evidence for real
permission revocation or recovery; no further host toggle is planned from it.

A later offline repair checks the actual Core Graphics tap state when deciding
whether a session is live. In a synthetic product test, a disabled tap with no
callback moves Collecting to Blocked and requires manual Start; 47 product
recovery tests and 65 capture-layer tests passed. This improves fail-closed
liveness but does not validate macOS permission revocation or the new bundle's
Settings identity. See [the scoped result](PERMISSION_RECOVERY_TEST.md#disabled-tap-liveness-fallback--2026-09-28).

At source commit `44e402d1edc7956f238cd1420875af5a17d0cbc4`, an unsigned
universal Release App built with arm64 and x86_64 slices. The exact executable
(`SHA-256 e2d51499ccc67f85f0223e6636aab5e26babfb6fc66b1476dabf4c45190c2a71`)
passed `Scripts/audit-product-network.sh` with zero matches; six
`PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed, including the
negative fixtures. Both macOS build CI jobs passed for this source commit.
This is a static capability result for that unsigned executable.

At PR #17 source commit `b188f5bd5ef5d731c7d96b6ac4fe13a4a1dd9bd6`, a fresh
unsigned Release App built with arm64 and x86_64 slices. Its exact executable
(`SHA-256 28ed199def331a6e20a00735c95c200f6179ab3f819a41807acac97b8cfc38ad`)
passed `Scripts/audit-product-network.sh`: 1,848 undefined-symbol lines and
20,069 string lines were inspected with zero matches. This qualifies only the
static audit of that unsigned candidate. The final signed Release executable
still needs its own audit.

At PR #17 source commit `1b9bf5adc13df5d3eb57a626cd13d82e17d4b524`, the
Debug journal counts visible snapshot and analysis assignments at their flow
boundary, including paused restoration. An older journal without the analysis
count is inconclusive for closed-interval publication evaluation. The focused
SwiftPM diagnostic, privacy-schema and evaluator tests passed; 11 native
snapshot-publication tests and the paused-restoration test passed. The unsigned
universal Release bundle passed the existing project and bundle boundary scans.
Its executable (`SHA-256 b25c1a800a3d02cc354cc34625e1cfa8ae804e5270727a8323f265e7efec6031`)
passed `Scripts/audit-product-network.sh` with zero matches. This does not
connect a live product observer to the hosted Keychain controller or audit a
final signed Release.

At PR #17 source commit `e550075ca3d6d325249196eb793e655ecbb2be0c`, an
unsigned universal Release App built with arm64 and x86_64 slices. Its exact
executable (`SHA-256 29feb7e48756d7002ed1c2dc03127342c8eb28c6ac9ff7ac340994ece19507ab`)
passed `Scripts/audit-product-network.sh`: 1,854 undefined-symbol lines and
20,192 string lines were inspected with zero matches. The executable has an
ad hoc signature and no Team ID. On this host, `security find-identity -v -p
codesigning` found zero valid identities, and the installed permission witness
trial has no embedded provisioning profile. These are current candidate and
host facts, not a signed Release audit or a usable permission trial. A final
signed Release executable needs its own static audit; the prior trial must not
be reused for permission qualification.

An isolated arm64 Debug package was also compiled from the same PR #17 source
with bundle ID `com.keyrecord.trial.permissioncandidate20260929`, display name
`KeyRecord Phase 1 Permission Candidate`, and the required trial-isolation
Info.plist marker set before the build. Its product dylib has SHA-256
`f3b79b50c9955b16914e9ae3009153fb43756523c1d37194383527679bb028d9`.
The bundle is ad hoc signed and has no embedded provisioning profile;
`launch-isolated-debug-trial.sh --check` rejected it with exit 2 without
launching. This is a compiled source candidate, not an operable host-trial
package. It must be rebuilt with a matching development signature and profile
before any permission or Keychain run.

## Dedicated trial isolation and bounded restart follow-up — 2026-09-27

PR #12 merged at `b57dbb796056e40d7967fea34879aedff39bbf4b`. This follow-up
protects explicitly marked Debug trial bundles against missing isolation variables
on system relaunch. The owner observed rejected startup without those variables;
an explicit isolated relaunch collected and saved one new shortcut, with the
published total advancing from 4 to 5, then exited normally.
See [the procedure, evidence and limitations](PERMISSION_RECOVERY_TEST.md#dedicated-debug-trial-relaunch-protection--2026-09-27).
Same-process real permission revoke/regrant behavior remains unverified. The synthetic
45/45 suite below is historical PR #12 evidence, not a new result for this follow-up.
No further host or performance round is scheduled; Phase 1/G1 and Release acceptance
remain open. Older dated sections below describe their respective historical states.

## Permission recovery coverage and evidence closeout — 2026-09-27

PR #11 merged at `94532b44ec3c021c569c5820fae340bfd888d5b7`, retaining the bounded
Secure Input fixture/evidence without the separate performance controller.
The [permission recovery regression](PERMISSION_RECOVERY_TEST.md) now covers the
product response to an injected live permission revocation, denial of Start while
permission is absent, no restart during a bounded grant-only observation, and explicit
Start followed by automatic persistence of one new count alongside two durable counts.
The new test passed alone and the complete synthetic recovery suite passed 45/45.
No product behavior changed. Real macOS revocation notification delivery and regrant
requirements remain unverified; Phase 1/G1 and Release acceptance remain open.
No new host or performance round is scheduled by this update.

## Worktree closeout and evidence order — 2026-09-27

This change retains the single-page Secure Input fixture and bounded Debug evidence.
A separate, unsubmitted synthetic performance controller is outside this change.
No additional resource run is scheduled. Existing paused and collecting-idle results
remain tied to their historical candidate, not current-main or Release acceptance.
Next, inspect product-level permission revoke/restore coverage before proposing any
bounded host operation. Do not restart the completed Secure Input round automatically.

## Historical PR #10 main: bounded Secure Input regression complete

Main is `64590a0e9b57a55af9a23921983f2c16bb59c62e`, the PR #10 merge containing
reviewed follow-up candidate `aee8649779f5d909fde86e989c1edadf5d31f457`.
An owner-operated, separate signed Debug arm64 build from this main completed the
single-page Secure Input regression: baseline 3 counts, no count increase inside
the witnessed closed interval, automatic capture/display recovery, 2 more counts,
and normal menu Quit. Eight issued writes returned successfully and were durable;
no failures/timeouts/invalidations were reported. No restart/decryption check was
performed in this round. See [the result and evidence](PR10_SINGLEPAGE_REGRESSION.md).

This closes the bounded post-repair Secure Input follow-up, not Phase 1/G1 or Release
acceptance. Formal typing/idle performance on ARM and actual Intel coverage remain open;
permission transitions, user switching, live network and Release qualification are also
open. Follow the work order above before asking for another host round.
The reusable [single-page procedure](PRIVACY_RESOURCE_USER_STEPS.md) requires no chat
replies while the field is focused. Trial launch uses explicit store/Keychain item
namespace isolation, not temporary HOME overrides.

## Post-merge follow-up under independent repair — 2026-09-26

PR #9 remains merged at `ec5583d73a1fc936bea1786708ba0717d8b47fbd`. The follow-up
`d89d5337` / `4c5d1665` adds automatic-persistence tests and changes Secure Input
monitoring and diagnostic boundaries; it is a separate candidate, not unchanged main.
The original agent reported approved, isolated Debug host observations for lock/Start,
Secure Input stop/resume and blocked Quit, plus one paused and one collecting-idle
resource window. See [the dated report](POSTMERGE_VERIFY_20260926.md) for exact source
attribution limits, observations and resource numbers. These are not formal performance
or Phase 1 acceptance. Directory modification times alone cannot establish no reads.

Independent review of `4c5d1665` found a Release compile error, an initial unknown
Secure Input poll that failed to close capture, a stale enabled read that could keep
restored statistics hidden, and a diagnostic interval ending after input could resume.
All three runtime boundaries have failing-first isolated regressions; the repair
restores fail-closed unknown handling, publishes the closing state before asynchronous
recovery, reconciles fresh disabled reads even for a live session, and ends the
interval before the new session accepts events. Release no longer depends on a
Debug-only latch. The repaired product commit `5072a1e2` passed 44/44 selected
recovery tests, 518/518 package tests, fresh unsigned Debug and universal Release
builds, and static Release/network audits. The latest validation is recorded in
the dated report; historical
host observations do not qualify this later repair.

Next: finish independent candidate review and CI, then decide whether to merge.
Any new real-host verification requires its own coordinated approval. Formal typing
and idle performance repeats, Intel runtime, permission changes, fast user switching,
measured network behavior and signed Release qualification remain incomplete. No
release, Phase 1/G1 acceptance or automatic permission to run host trials is implied.

## PR #9 merge checkpoint — 2026-09-26

[PR #9](https://github.com/fhtpku-Cli/KeyRecord/pull/9) is merged into `main` as
`ec5583d73a1fc936bea1786708ba0717d8b47fbd`, containing reviewed candidate
`205d10c61ce69274dcead3a9de85dd2259cecf5c`. Local `main` is at this merge commit.
The original measurement worktree and local evidence were retained. The dated
sections below describe historical candidates, not fresh verification of this merge.

The PR includes privacy monitoring, recovery/termination and reset/erase recovery
repairs, plus opt-in diagnostic and resource-measurement preparation. The final
candidate changed recovery-test synchronization: fixture preparation awaits actual
save completion and joins previously issued background work, instead of inferring
durability from two state reads separated by an `await`. Product recovery logic was
unchanged by that final synchronization revision.

Independent review of the final increment and relevant call paths found no blocking
defect. On `205d10c6`, a fresh unsigned Debug arm64 hostless App test build passed
two complete `ProductRecoveryQuitTests` runs: **40/40** in 41.897 seconds and
**40/40** in 41.775 seconds. The reviewing coordinator separately executed the
disk-before/disk-after synchronization regression: **1/1** passed. Existing count,
cycle, privacy and injected-failure assertions were retained. Local review reports
and raw logs are under `.omo/evidence/pr9-independent-review-205d10c6/`; these
untracked artifacts are not guaranteed to be present in a fresh clone.

Both pre-merge macOS CI builds passed on `205d10c6`. Security and approval checks
reported success; Bugbot was quota-limited and did not provide a valid fresh review.
CI omits App XCTest execution, so the independent App runs are separate evidence.
The reviewing coordinator did not independently rerun the earlier 517-package-test
claim or universal Release build. These results are candidate-specific and are not
new executions on the merge commit or evidence of signed Release qualification.

### Verification sequence planned at the merge checkpoint (historical)

1. **Automatic persistence, isolated and offline:** exercise normal product pulse
   wiring with synthetic input and a temporary encrypted store. Observe expected
   durable counts before any explicit flush, Quit or teardown save; verify a later
   input batch persists without loss or duplication. The existing explicit-save
   recovery tests do not qualify automatic save cadence.
2. **Prepare a separate current-main signed Debug candidate:** identify source and
   build settings, verify trial store/Keychain isolation, and prepare bounded run
   instructions and diagnostic paths without replacing or launching the daily app.
3. **Separately approved host rounds:** lock/unlock with explicit Start; independently
   witnessed Secure Input enable/disable with stop/automatic recovery; and Quit while
   blocked. Record state transitions, interval counters, durable results and actual
   termination. Endpoint screenshots alone do not prove continuous privacy closure.
4. **Resource measurement after functional checks:** measure collecting and paused
   behavior, including Secure Input monitoring overhead, under the existing
   [protocol](PRIVACY_RESOURCE_PREP.md). Preserve interrupted/invalid results and
   distinguish exploratory local measurements from formal ARM/Intel qualification.

At this merge checkpoint no current-merge live trial or resource result was claimed.
Later candidate observations and their limits are described above. Further live launches
and host/privacy operations require approval for the particular round. Phase 1/G1,
permission changes, fast user switching, measured network behavior, other hardware
and signed Release qualification remain incomplete; see the
[acceptance matrix](PHASE1_ACCEPTANCE.md). This is verification follow-up, not a new
gate or authorization to weaken existing privacy or Release restrictions.

## Repaired candidate bounded acceptance — 2026-09-24

The paused-restoration and flush-diagnostics repair (based on main `3b9345c`) was built and development-signed as a separate candidate. Two owner-assisted repair rounds passed: paused restart directly displayed retained statistics without capture or writes; Resume/input/Quit followed by paused restart retained exact Command-A groups 13 and 11. Both final launches exited 0; the collection run recorded 9 issued/returned/succeeded/durable writes, zero invalidations/failures/timeouts, and the paused restart recorded zero capture/write events. See [the detailed acceptance record](CURRENT_MAIN_ACCEPTANCE.md) for owner-report versus screenshot evidence and candidate paths.

These observations qualify only the bounded repaired Debug candidate, not Release. The old 38/37 discrepancy remains historically unexplained. Full privacy, monitor performance, analysis/menu/accessibility qualification are still pending; the two bounded repair-specific manual rounds are complete. The owner separately authorized commit, review, push and merge on 2026-09-24. Further live launches require a separately coordinated approval.

## Earlier main verification preparation — 2026-09-22

Read-only GitHub verification confirms PR5, PR6 and PR7 merged. Remote main and the clean starting checkout both resolve to `3b9345c30086e9e33c4510047e2692337f5b8643`; its tree matches reviewed PR7 head `c242def7253bf8610896f6290b072a71a75d8b82`. Main CI [35721067804](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/35721067804) completed successfully at the final preparation check. A fresh unsigned arm64 Debug/test build and 20 selected synthetic hostless tests also passed; see the candidate plan for logs and limits.

On 2026-09-23, owner-approved use of the signed current-main Debug candidate observed Command-A totals 15→18, paused-input totals remaining 18, subsequent totals 21 with login-startup display still enabled, normal quit, and restart plus explicit resume retaining 21. Final exit was 0 with 4 issued/4 durable writes and no reported write/read failures or timeout. Paused restart alone showed privacy-hidden statistics: the existing paused startup skips readiness/capture and does not restore aggregates until Start/resume. An earlier run had 38 issued/37 durable writes; that discrepancy remains unresolved, and target-count retention does not prove every write completed.

These are bounded target-count and owner-observed UI results, **not complete real-use acceptance**. Recommendation/analysis display, physical menu-bar status, actual dead-session recovery, continuous privacy and formal performance/Release qualification remain pending. PR7's 24 selected regressions and independent 20-test QA retain their synthetic publication scope. [Current-main acceptance record](CURRENT_MAIN_ACCEPTANCE.md) provides candidate/session details and limits. Historical sections below retain their original scope.

## Phase 1 acceptance work

The [2026-09-22 offline closeout report](PHASE1_CLOSEOUT_20260922.md) records new isolated
regressions, unsigned build/static checks and verification-tool repairs. These do not
qualify the current signed product, real Keychain or G1 performance.

Use [PHASE1_ACCEPTANCE.md](PHASE1_ACCEPTANCE.md) for the remaining requirement/evidence matrix,
safe automated commands, performance protocol and minimum owner-assisted steps.
[MILESTONE_STATUS.md](MILESTONE_STATUS.md) and [EXECUTION_CHECKPOINT.md](EXECUTION_CHECKPOINT.md)
are historical snapshots, not the current list of runtime defects. The bounded observations
below remain bound to their recorded candidate; Phase 1/G1 and live Release qualification
remain incomplete.

## 2026-09-22 host follow-up and merged repair

PR #3 was merged into `main` as `3f9f31aa0705b750f9c460fd0a37195b94b19ea9`; its tree matches the reviewed `e83e86193f7eecfff23b941c966988864e9d9207`. The final repair revision passed 479 package tests. Both PR/push CI and the subsequent main CI passed. The 42 App boundary/reduction tests and Debug/universal Release builds were measured at `6860c8024f333a01689252d0c9c7f7c347a9895f`; later pre-merge changes were documentation and a deterministic test-overlap correction, not production changes.

Subsequent owner-approved bounded runs of the existing signed Debug candidate observed:

- Lock/unlock followed by explicit menu **Start** restored the aggregate display. One subsequent TextEdit shortcut increased its combined modifier groups by one.
- A system power log confirmed an actual manual sleep and wake, despite existing sleep-prevention settings. After explicit **Start**, displayed prior counts remained and a subsequent TextEdit shortcut increased its combined groups by one.
- During the requested TextEdit exclusion sequence, target counts were unchanged after the excluded inputs and increased by one after exclusion was disabled. The owner later confirmed TextEdit's exclusion switch was off, the requested final setting.

These are single-host, bounded behavioral observations, not complete lifecycle/privacy qualification. Screenshots do not establish zero capture throughout a locked interval; numeric lifetime summaries do not identify individual inputs or prove every intermediate UI state. Exclusion screenshots do not independently show toggle state. Successful termination summaries report no write failures/timeouts, but one lock-recovery run had unequal issued/durable counts and is not proof that every issued flush completed. Later sleep/exclusion summaries had matching counts. A first incomplete lock trial ended by SIGTERM without a summary and is not a successful persistence test.

The signed candidate came from the modifier-display Debug build, before the later movement of diagnostic-path lookup from `ProductComposition` into `AppDelegate`. It was not rebuilt from merged main for these runs. That known change concerns shutdown diagnostics, not modifier reconstruction; source comparison cannot turn the older binary into a qualification of current main or Release. Local provenance and raw evidence remain under `.omo/repair-20260921/{modifier-display,input-pr,lock-validation,sleep-validation,exclusion-validation}/`.

Repeated first inputs reported an unknown modifier side even when the owner used left Command. The adapter supplies family flags and the queue reconstructs sides from observed transitions. A fresh or recovered queue has no observed released state: its first Command change can mean a press or a release while the opposite side remains held. Unknown is therefore a supported outcome, even if a flagsChanged event arrived. An observed release followed by another press permits side recovery. The existing host evidence does not identify the precise event history, so a lost-event or driver fault is not established, and no side is guessed to make the label look precise.

Remaining work includes current-candidate host verification where needed, time-resolved privacy-boundary evidence, permission changes, fast user switching, signed Release and formal hardware/performance/network qualification. Release capture remains blocked. The historical sections below retain their original scope; the bounded observations above supersede only their corresponding pending host scenarios.

## 2026-09-21 bounded input and restart follow-up

Owner-approved runs of the signed Debug product observed three deliberate TextEdit shortcuts added to the displayed aggregate and retained after a normal quit/restart. Two previously identical-looking rows were separate modifier-state groups (side unknown and left). The display now names left/right/both/unknown modifier states and unknown Fn explicitly, without changing grouping or stored counts. English and Chinese synthetic SwiftUI screens were checked in light/dark appearances at normal and narrow widths.

An explicitly enabled DEBUG-only run summary survives per-session diagnostic resets and records numeric counters, successful model-publication totals and read failures on normal termination. It contains no input text, key codes, application identifiers or event timestamps. Model publication is not proof of screen rendering; the bounded owner screenshots provide that separate observation. A crash or forced kill may produce no summary.

At `b46316bbb7c4c0dcc7573619010ae5eecc6eabcb`, final automated verification passed 476 package and 114 App tests with no failures/skips; both GitHub push and PR CI builds passed. The follow-up changes have their own focused regression, localization, native-rendering and build checks; do not treat the older full-suite count as measurement of a newer revision. Local follow-up evidence is under `.omo/repair-20260921/{diagnostic-followup,modifier-display}/` and is not bundled with releases.

This establishes bounded physical-input, observed application attribution, displayed increments and restart persistence on this host. It does not qualify all foreground transitions, exclusions, lock/sleep recovery, signed Release, Intel performance or full G1/public release. No historical formal receipt or milestone gate is rewritten. The earlier repair narrative below records earlier checkpoints; its then-pending capture/CI observations are superseded only by the scoped results above.

## 2026-09-21 repair status (earlier checkpoint)

The 2026-09-21 local repair is implemented on `codex/phase1-repair-20260921` based on `6687c296dbf44abe34f78055e7f830dfbe30771a`. It fixes unknown lock-state fail-closed behavior, Release diagnostic isolation, application attribution/session recovery, unsaved-data protection, production-layer counters, keyboard accessibility and reproducible App testing. Phase 1 still requires bounded real-host validation; it is not reliable-daily-use, full G1 or public-release acceptance.

Fresh final verification on macOS 27.0 (26A428), Xcode 27.0 / Swift 6.4: SwiftPM 476/476 passed (Core 216, Capture 64, Store 157, Integration 39), App hostless XCTest 104/104 passed, zero failed or skipped. The focused lock/reduction/accessibility group passed three consecutive 26-test runs. SwiftPM Release, unsigned App universal Release (arm64 and x86_64) and native Debug test compilation passed. Independent safety rereview cleared two additional repaired recovery races. Build logs retain existing compiler warnings; these results do not claim a warning-free toolchain. Local raw logs are in `.omo/repair-20260921/`, with the reproducible workflow transcript at `verify-local.log` and final results in `final-*.log`. GitHub CI configuration is added but has not run remotely.

The first user-assisted read-only cycle returned `unknown → locked → unknown` through the CGSession field. A second approved 60.4-second cycle found explicit `unlocked → locked → unlocked` through the root IORegistry `IOConsoleLocked` boolean, with matching foreground-session checks throughout. The DEBUG provider now combines explicit witnesses with current-user foreground-session checks before and after the console read; any locked witness or lock notification blocks, and missing/malformed evidence cannot default to unlocked. A read-only driver of the actual provider returns `unlocked` on this host. This is an experimental development implementation: the two system reads are not atomic, and fast user switching, sleep, product notification transitions and physical capture remain unqualified. See `.omo/repair-20260921/CONSOLE-WITNESS-INVESTIGATION.md` and `console-lock-fix-result.md` for the follow-up results; the earlier 104-test full run predates this follow-up.

The 2026-09-20 review at `6687c296dbf44abe34f78055e7f830dfbe30771a` measured 459/459 SwiftPM tests passing, SwiftPM Release compilation passing, native unsigned Debug App test compilation passing, App XCTest 71 pass / 20 fail / 1 skip, and unsigned App Release compilation failing. The App run did not supply `T23_RELEASE_APP`, so Release-dependent failures included an unmet test prerequisite. These are pre-repair measurements, not the current repair's results. Earlier claims of only 14 App failures, a usable current Release bundle, and completed product capture qualification are superseded.

The current product physical-input → attribution → durable-save → restart closure remains pending. A prior bounded harness observation with Karabiner running shows that physical events reached that harness at that time; it does not rule out every driver interaction or verify the product pipeline. The verified DEBUG diagnostics wiring enables measurement and does not by itself prove this closure.

Use [README](../README.md#build-and-test) and `Scripts/verify-local.sh` for ordinary development verification. CI deliberately omits App XCTest and real-host operations; successful unsigned universal compilation is not signing, Intel runtime, or host qualification. The portable normative requirements are in [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

The sections below retain historical checkpoints and existing qualification rules. Their measurements and old handoff references apply to their stated revisions, not automatically to this repair. No historical receipt, sealed evidence or formal blocker is rewritten or waived. Signed lifecycle/lock/keychain qualification, network and ARM/Intel performance, hosted UI/accessibility and FR-P6 remain independently pending or blocked as documented in [MILESTONE_STATUS.md](MILESTONE_STATUS.md).

## Authority and reproduction

This is the current-status entry point, not a new Phase 0 conclusion or a release approval. The repository-contained [approved contract](PHASE1_CONTRACT.md#allocation-and-owner-approval) establishes precedence: owner contract > PRD normative behavior > architecture normative behavior > verified current evidence for measured facts. Requirement allocation and implementation constraints are in [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

The observation below was rechecked from a clean schema-v1 projection at base `064164e47fe2dfb1957ea8fc601269ecb2c8812e` in T24. Exact attempt identities are in the milestone report. It is not a promise about a later checkout. Generate a fresh, nonexisting output under the current attempt, then validate it using the built `EvidenceValidator`:

```sh
"$VALIDATOR" current-readiness --historical evidence/phase0 --lifecycle none --output "$A/current-projection.json"
"$VALIDATOR" verify-current-readiness "$A/current-projection.json"
bash Spikes/Scripts/verify-current-deliverables.sh "$A/current-projection.json" --validator "$VALIDATOR" --gate all
```

Generation/verification returning 2 means a valid BLOCKED projection, not a parsing failure. The [schema](../Spikes/Sources/EvidenceValidator/CurrentReadinessModels.swift) defines `historicalAssessment`, `bindings`, `gates`, `localLifecycleAssessment` and `retainedReleaseBlockers`; [validation](../Spikes/Sources/EvidenceValidator/CurrentReadinessValidator.swift) checks bound Git identities, exact bytes, strict decoding and semantic recomputation. `status` is computed, not a writable JSON status field. Neither a document title nor a prose keyword is proof. Publishing `evidence/phase1/readiness.json` belongs to task 15; this task does not publish it.

## Parsed current state

Selectors below refer to the validated current projection, with array rows selected by exact `id` (not position or phrase matching).

| Claim / reference ID | Parsed field | Observed value and limit |
|---|---|---|
| current-g0 | `gates[id=G0].status`, `.unresolvedCauses` | PASS, `[]`; verified bound historical proof, not a new live run |
| current-history | `historicalAssessment.g0.status`, `.candidate_selection` | PASSED, session; attribution remains the historical source/generator identities |
| current-o6 | `historicalAssessment.o_items[id=O6].status`, `.evidence_paths`, `.blocker_refs` | RESOLVED, `[sp2/evidence.json]`, `[]`; only the bound SP2 generation, not arbitrary macOS versions |
| current-lifecycle | `localLifecycleAssessment`; `gates[id=SP6A_LOCAL_LIFECYCLE].status`, `.unresolvedCauses` | BLOCKED: `receipt.keychainPolicy`, `receipt.sessionLock`, `receipt.restart`, `receipt.sleepWake` |
| current-implementation | `gates[id=G1_IMPLEMENTATION].status`, `.unresolvedCauses` | BLOCKED: `SP6A_LOCAL_LIFECYCLE`, `receipt.capture`, `receipt.privacy`, `receipt.encryptedPersistence`; G0 is no longer a current cause |
| current-release | `retainedReleaseBlockers[].id`, `.caused_by` | KARABINER_STABLE: `sp3.versionSample`, `sp3.reload`, `sp3.disableLatency`; VIA_GENERATION: `sp4b.deviceProtocol`, `sp4b.keycodeDialect`, `sp4b.importer`; VIAL_BETA: `sp5a.importer`, `sp5b.liveCapture`; FULL_BACKUP_FINAL_RELEASE: `sp6b.intelTiming`, `SP-6B dependency_frozen=false` |
| current-binding | `bindings.commitSha`, `.treeSha`, `.files[].path`, `.files[].sha256`, `.missingPaths` | Recomputed for each checkout; a missing proof blocks and a stale or forged binding fails. Never reuse a projection after changing its bound inputs or HEAD. |

FR-P6 full password backup remains independently required: neither local-storage qualification nor G0/implementation tests waive or pass it. The current schema's G1_IMPLEMENTATION receipt gate is not the entire normative G1 exit: architecture §12.4 ARM + Intel product-performance evidence is additionally required, independent of SP6B Intel KDF timing. Pure tests do not establish signed lifecycle, network or performance evidence. CLI receipt producer approval is empty until an authorized producer is integrated; self-authored receipt claims cannot earn PASS.

## Historical descriptions, not current authority

Line references in this section are pinned to `985d6af`, so bounded insertions in working documentation do not obscure the original locations. Sealed `evidence/phase0/**`, old candidate/receipts and ConclusionGenerator v1 remain byte-identical; no measured history is regenerated to repair wording.

- **SP1 selected-NONE is historical/stale prose:** `evidence/phase0/sp1/SP-1-CONCLUSION.md:5–7` says selected NONE / G0 OPEN even though parsed bound `historicalAssessment.g0` selects session and is PASSED. Preserve the file; do not use its words as a current gate.
- **SP2 no-sleep is historical/stale prose:** `Spikes/Sources/Phase0Probe/SP2Probe.swift:156–158` emits the no-sleep description at line 157; the stored `evidence/phase0/sp2/SP-2-CONCLUSION.md:9` carries that description. Read bound SP2 leg verdicts and O6 disposition instead; this note authorizes no sleep or host operation.
- The **old static dependency list** at `docs/TECHNICAL_ARCHITECTURE.md:889–891,957` and `historicalAssessment.downstream_blocks[id=G1].caused_by` describe the historical dependency model, not the recomputed current causes. G0 must not remain permanently OPEN in current acceptance.
- Stale local status prose at architecture `213,237,274,379,388,938,967` and PRD `673` is labeled beside its location. It cannot override parsed current fields or expand the measured support envelope. ADR-010's pending-review wording at architecture `974` predates the owner approval below.
- `Spikes/Scripts/verify-plan-deliverables.sh:11–27` is the **historical baseline**, unchanged; its OPEN checks and old plan-checkbox checks are not current acceptance.

## Owner-approved lock and reset contract

Owner-approved behavior (2026-09-12), reproduced in the portable contract: “screen/session lock stops capture and protected-data reads; invalidate volatile key handles and sensitive UI snapshots, resume only after unlock plus fresh key/privacy checks and only if `expectedCollecting` remains true. Do not promise guaranteed zeroization of copies managed by Swift/CryptoKit.”

Reset removes daily details and retains exactly architecture §5.1 CycleSummary fields: `cycleId`, `perChordTotals: [(chord, appBucket, total)]`, `perBareKeyTotals: [(keyCode, total)]`, `distinctActiveDays`; plus existing mappings/backups/ignored items/preferences. No day distribution, `sourceCounts`, `kind` or `scopeClass` survives in the summary. This is approval of behavior, not evidence of implementation. See [contracts 8–9](PHASE1_CONTRACT.md#8-durability-and-lock).

## Acceptance scope

The new checker defaults to `--gate G0`: exit 0 means the verified historical prerequisite is satisfied, **not** G1 or release. It always reports `scope`, overall `readiness_exit`, and `release_claim=false`. `--gate all` preserves the full current-readiness outcome; other gate IDs are explicitly selectable. Missing proof is BLOCKED/2; malformed/tampered/waived evidence is FAIL/1. `--candidate <file>` additionally delegates to task 4's `verify-current-candidate <file> --readiness <file>` when available; unavailable/invalid candidate validation never silently passes. No plan checkbox or document phrase grants acceptance.

`CurrentDeliverablesTests/testHappyReviewerReferenceTable` prints parsed claim-to-field pairs for each bounded status note. These synthetic tests prove acceptance behavior, not current host capabilities; use a fresh real projection for the observed state above.

---

## Corrective round 2026-09-18/20

Scope-limited round on capture, privacy, lifecycle, persistence and exclusion wiring.
It changed no evidence schema, published no projection and claims no gate transition:
every BLOCKED gate above stays BLOCKED, and this is not a G1 or release claim.

Baseline `45d2ba8a1` -> `36d9115d7`, eight commits, 40 files, +3515/-185.

### Defect classes fixed

Seven came from a 2026-09-18 review; six more surfaced only during host verification.
Root causes worth remembering, because each was invisible to the tests that existed:

- A provider assigned **after** `init` returned, so the observer block registered inside the
  initializer captured `nil` - screen lock and unlock were never observed at all.
- The permission gate ran **after** provider validation, so the single production call to
  `CGRequestListenEventAccess()` was unreachable in a stable denied state: the user could
  never be asked.
- Production `FlowActions.loadChoices` was left at its default empty closure, so the
  exclusions list was permanently empty while previews and UI doubles looked correct.
- The status title consulted only lifecycle phase and the key gate. Both look healthy at
  boot, so the menu bar showed "Collecting" with zero store handles and zero counts.
- Recovery called a policy-refresh helper that never starts the event source, then asked
  whether a session was live - necessarily false, so every recovery reported `startFailed`.

### Test counts

Baseline measured 379 executed / 364 passed / **15 failed**. Those 15 were **validator
faults, not product defects**: a crash probe that searched for a build layout the current
backend never emits, and a scratch-directory helper that required an ancestor literally
named `build` (the default is `.build`). After the round: **459 executed, 459 passed, zero
failed, zero skipped**.

Correction from the 2026-09-20 raw-log review: the earlier baseline App log contains 61 pass / 19 fail / 1 skip; the corrective round final log contains 67 pass / 23 fail / 1 skip. The prior 14-failure/identical-set claim was incorrect. Counts are test cases, not assertion totals. The newer review measured 71 pass / 20 fail / 1 skip under its stated prerequisites; none of these failures is waived.

### Historical harness observation

Earlier investigation notes speculated that Karabiner's DriverKit layer was swallowing
physical key events. A bounded 45-second host run with **all four Karabiner daemons
running** observed tap keyDown 168 / keyUp 168, queue accepted 336, normalized 336,
aggregate delta 168, zero closed handoffs and zero tapDisabled events.

That observation refutes the narrow hypothesis that all physical events were swallowed before reaching that harness during that run. It does not establish the cause of the product failure or permanently exclude Karabiner interactions. Secure Input remains an unproven candidate, not a diagnosis.

### Historical gap before the 2026-09-21 repair: layered counters

At this checkpoint, `CaptureDiagnostics` reports which layer of the capture chain stopped, but its per-layer
counters are incremented only by the test harness and unit tests - **never by the shipping
app**. Until they are wired, the chain is verified only as far as "a session exists"; whether
events actually reach the aggregate and become durable has not been observed in production.

The diagnosis now states `counters are not instrumented in this build` rather than reporting
an unwritten zero, because reading one as a measurement previously produced the fabricated
claim that no keyboard event had reached the process.
