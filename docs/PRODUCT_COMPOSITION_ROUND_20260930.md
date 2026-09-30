# Full product Keychain round: first execution and diagnosis

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
