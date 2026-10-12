# Full product Keychain round: execution and recovery result

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round.

## Current result: unlocked full-product scenario passed

After the owner confirmed normal unlock, a read-only readiness check reported
`console=unlocked`, on-console true and matching current user. The session lock
key was absent (`session=unknown`); this check is readiness evidence only.
The existing signed `fee7d4aef` Products were copied unchanged into a fresh round,
independently reviewed, and used without rebuilding, resigning or installation.
The previous two rounds and their outputs remain intact.

The exact selected test
`HostedProductCompositionTests.testAuthorizedProductCompositionWithRealKeychainAndSimulatedInput`
passed in 7.564 seconds. The xcresult reports one passed, zero failed/skipped and
no runtime warnings. The controller finished in 12.236 seconds with exit 0,
no forced stop, no control errors and no remaining exact host; independent
presence inspection also found none. The log reports `COMPOSITION cleanupVerified=2`.

This executes actual product composition, encrypted storage and the App backend
against real data-protection Keychain items in a fresh private namespace. Two
fixed simulated inputs save and read back as two; simulated lock closes admission
and key access. Bounded closed and unlock-before-Start windows report zero
protected-read/publication/aggregate deltas. Explicit recovery reads two, then a
new composition/store in the same process reads two and saves a third input.
Both successfully created test items are deleted and their absence is verified.

Artifacts: `/private/tmp/keyrecord-product-composition-unlocked-20260930`, including
`keychain-run.json`, `keychain-run.log`, `keychain.xcresult`, `host.json`,
`keychain-approved.xctestrun` and the service-only namespace record. Its
`result.json` retains the original diagnostic signing result (21.076 seconds),
with explicit reuse provenance; that duration is not a new signing run.
The round is consumed. Its output directory and namespace must not be reused.
Independent post-run review also confirmed this result and scope in
`/private/tmp/.omo/evidence/composition-unlocked-result-code-review.md`.

This closes unlocked full-product recovery for this signed candidate. Actual OS
lock transitions, initial startup under lock, separate-process restart, continuous
privacy coverage and rendered UI remain outside this scenario. Independent
production lock authority and collecting Release remain unqualified. No system
permissions or product safety behavior changed, and no ordinary input was captured.

## Earlier diagnostic failure and locked readiness

The separately reviewed diagnostic source `fee7d4aef` signed successfully in
21.076 seconds using the existing profiles. Actual-artifact review and read-only
preparation passed before its single automatic test launched. The test then failed
in 7.412 seconds with these coarse observations:

- `step=start`, `phase=failed`, `keyProvisionFailed(unavailable)`.
- First failing client operation: `add`, OSStatus `-25308`.
- Successfully created items: zero; cleanup verified zero owned items.
- Controller: 12.305 seconds, exit 65, no forced stop, no control errors and no
  remaining exact host. Independent process inspection agrees.

The exact xcresult summary reports one failed test, zero passed/skipped and no
runtime warnings. `-25308` is `errSecInteractionNotAllowed`; it does not by itself
prove that the screen was locked when the operation failed. A subsequent read-only
check of the same coarse lock inputs used by the existing Debug provider reported
`console=locked`, `session=locked`, on-console true and matching current user.
That establishes a current readiness obstacle, not a historical or version-wide
lock qualification. No product logic or Keychain policy was weakened.

Artifacts remain under
`/private/tmp/keyrecord-product-composition-diagnostic-20260930`, with the same
result/log/xcresult/service-record names as the first round. This round is also
consumed. The reviewer independently confirmed the add rejection and zero created
items. At this checkpoint actual Keychain retries stopped until the owner unlocked
this Mac and confirmed readiness. No permission toggle, Keychain setting change, authentication
prompt handling or extra signature is needed merely to resolve readiness.
The existing signed diagnostic artifact can be reused for a newly isolated,
reviewed round; the prior outputs must remain intact.

## Authorization and independent review

On 2026-09-30 the owner authorized subsequent signing and automated verification
to proceed after independent sub-agent review, without another routine approval
question. This covers the prepared isolated rounds; it does not authorize changing
system permissions, entering credentials, capturing ordinary input or accessing
daily stores. Work requiring the owner's physical action still stops for readiness.

The reviewer blocked the original private signing controller because an exception
or interruption could leave its independent build process group running. The
controller now handles SIGTERM/SIGINT and exceptions with bounded TERM/KILL cleanup,
requests stopping at 110 seconds, and forces termination by 115 seconds. Seven
synthetic cases passed both the executor's and reviewer's runs. Review then passed
for signing and, separately, for the actual signed files before automated testing.

## Observed result on source 331a8e4e1

Signing succeeded in 22.311 seconds using the existing profiles and certificate,
without provisioning updates. No build process group remained. Both exact bundle
signatures, identities and host/plugin entitlements passed read-only inspection.
Embedded profile UUIDs are unchanged from the prior approved backend round.

The one selected full-product real Keychain test **failed**, with a generic
`timeout` after 7.686 seconds. The controller finished in 11.704 seconds with exit
65, no forced stop, no control errors and no remaining exact host. Independent
presence inspection also found no probe. The exact xcresult node confirms one
executed failure, not a skip or a passing run.

The new private store directory exists but contains no files. That supports an
early initialization failure; it does not identify its cause. The fixture catches
the scenario failure, completes cleanup for successfully created items, then
rethrows the original error. No cleanup failure was reported. This version did
not record how many items it created, so no item-count claim is made.

Artifacts are retained under
`/private/tmp/keyrecord-product-composition-signed-20260930`: `result.json`,
`build.log`, `host.json`, `product-composition-service.txt`, `keychain-run.json`,
`keychain-run.log`, `keychain-approved.xctestrun`, `keychain.xcresult`, and the
isolated store directory. These output names are consumed and cannot be reused.

## Diagnostic follow-up

The fixture's timeout originally hid which condition was unmet. It now identifies
the step, lifecycle phase/failure, blocked reason and coarse load classification.
The test-only Keychain wrapper records the first failing operation with its
OSStatus or authorization rejection, plus a count of owned items. It never records
key bytes or input content. Cleanup completion is explicitly counted.

An offline case with 100 ms authorization delay per operation passes the complete
scenario in 6.394 seconds. This does not reproduce the signed failure and does not
justify increasing its timeout. A separately reviewed diagnostic round is needed
to identify the real failure before any product behavior is changed.

The final unsigned Debug build and selected XCTest run pass: 17 offline cases,
zero failures, with both real-Keychain opt-ins skipped. The complete fast and slow
scenarios each report two owned items cleaned up. Logs are
`/private/tmp/keyrecord-composition-diagnosis-final-build.log` and
`/private/tmp/keyrecord-composition-diagnosis-final-tests.log`; the initial delayed
case is in `/private/tmp/keyrecord-composition-slow-tests.log`.

The fixed input and distributed lock notifications are simulated. The actual
composition still observes NSWorkspace sleep/session notifications, which can
close the test safely if the host changes state; those observers were not replaced.
No actual lock/sleep transition, physical keystroke or permission change was
requested. Independent lock authority and collecting Release remain unqualified.
