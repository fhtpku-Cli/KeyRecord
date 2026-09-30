# Secure Input clearing during rebuild

An offline 64-case product recovery run exposed a timeout in
`testPauseAndQuitStopTheMonitorAndClearingSecureInputCannotReopen`: after Resume,
turning Secure Input on and quickly off could leave capture waiting for a manual
Start. This was not dismissed after a successful rerun.

A deterministic regression holds the failure-settlement provider read. The
rebuild's fresh conditions, policy and readiness reads see Secure Input enabled;
the held read completes only after it becomes disabled. Before the repair, this
case consistently times out waiting for automatic recovery. The original suite
failure is in `/private/tmp/keyrecord-product-backend-recovery-suite.log`; the
exact settlement reproduction is in `/private/tmp/keyrecord-secure-settlement-red-exact.log`.
An earlier reproduction held the preceding readiness read and also failed; it is
retained as `...-secure-settlement-red.log`, not mislabeled as the settlement read.

The composition now retains the fresh Secure Input condition supplied to the
failed rebuild. Settlement considers both that condition and its subsequent
provider read. A temporary Secure Input rejection remains with the existing
monitor, which performs fresh privacy checks before reopening. An ordinary failed
rebuild with Secure Input known off still hands over to explicit Start. Permission
revocation, screen lock, user pause and quit keep their existing priority.
No qualification, Keychain, signing or Release restriction was removed.

The fixed reproduction saves the two retained counts and one new count after
automatic recovery. It passes together with the original failing case, genuine
failed-rebuild handover and permission loss during settlement (four focused cases).
Debug test compilation and unsigned native Apple Silicon Release compilation pass.
The complete affected recovery/quit suite then passes all 65 cases with zero
failures/skips. Logs: `/private/tmp/keyrecord-secure-settlement-green-focused.log`,
`/private/tmp/keyrecord-secure-settlement-green-suite.log`, and
`/private/tmp/keyrecord-secure-settlement-release-build.log`.
The existing static network audit of this exact native Release executable reports
zero matches (`liveReceipt=false`); it is not a network observation or permission
to enable collection.
This is offline product-composition evidence; no Secure Input setting, permission,
keychain item, sleep or lock operation was performed on the system.

## Product backend recovery integration

The same fixture can now supply the real `LocalKeychainBackend` with an in-memory
Security client. The lock/unlock observer case uses that backend, demonstrates
actual instrumented Keychain-read attempts during operation, no client queries in
its closed interval, and fresh queries only after explicit Start.

A second case retains metadata but removes the current key material from memory.
The product remains closed; every existing encrypted file is unchanged and no
replacement key is created. Restoring the original material allows the full
composition to recover its saved count of two and continue to a durable count of
three. The prior simplified backend enumerated actual in-memory key entries,
whereas the real backend's metadata can still name a missing key; the new case
covers that integration difference.

These checks use real product lifecycle/reducer/store/backend code with synthetic
OS providers, input and Security results. They do not replace the separately
recorded real [unlocked Keychain result](PRODUCT_KEYCHAIN_ROUND_20260930.md) or
establish live lock authority/full signed product recovery.
