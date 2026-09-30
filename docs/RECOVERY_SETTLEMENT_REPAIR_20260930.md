# Failed recovery settlement repair

An offline full ProductRecoveryQuitTests run exposed an intermittent failure in
`testFailedAutomaticRecoveryLeavesAnActionableState`: privacyCheckRequired replaced
keyUnavailable, and the retained-count check timed out. Isolation and a quiet
61-case rerun passed, so those reruns did not establish correctness.

A deterministic synthetic reproduction parks the collecting monitor, scripts the
three recovery Secure Input reads, then parks settlement's fourth read after a
failed foreground rebuild. Releasing only the monitor reproduces four failures:
the phase becomes Blocked, the key gate closes, the reason becomes privacyRequired,
and the encrypted-store total after explicit retry is one instead of two.
Log: `/private/tmp/keyrecord-recovery-settlement-red.log`.

`runtimeReconciliations` previously ended when the coordinator returned, before
settlement's asynchronous checks and retained-count flush. The health monitor
could therefore mistake the known stopped source for an unexpected stop and
discard the retained aggregate. Settlement now runs inside the existing
reconciliation lifetime. Lock, permission and Secure Input checks still execute
independently of the session-health stability condition.

The same reproduction and original failing case both pass after the repair
(two cases, 1.952 seconds). A second regression parks settlement and revokes the
fake permission, verifies privacy closure, and verifies explicit Start still
fails with the gate and capture closed. Its initial assertion incorrectly expected
Blocked after Start; the existing denied-Start contract and observed result are
Failed. Only that new assertion was corrected; closure assertions remain.

Final Debug build-for-testing succeeds and all 63 product recovery/quit tests pass
(65.599 seconds), including both new interleaving cases and the permission witness
cases. Log: `/private/tmp/keyrecord-recovery-settlement-product-final.log`.
The final unsigned arm64 Release rebuild also succeeds, and the existing static
product network audit reports PASS with zero matches. This does not enable Release
collection. Build log: `/private/tmp/keyrecord-recovery-settlement-release.log`.

These tests use fake host providers, an in-memory Keychain and private synthetic
encrypted stores. They establish the product recovery behavior under controlled
interleaving, not a new live Input Monitoring or hosted Keychain qualification.
The installed owner-approved chord candidate is not replaced by this repair.
