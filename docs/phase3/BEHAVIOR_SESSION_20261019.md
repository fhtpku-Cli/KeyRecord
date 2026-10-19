# Karabiner application behavior test session

Previously, the native verification action only compared configuration bytes.
Core reconciliation removed every temporary draft on an ordinary refresh, so
there was no usable application test session spanning the configuration watcher.
There were no native start, result, cancel or quit-cleanup actions.

The application now prepares application-scoped drafts through the existing
conflict, compatibility, profile, runtime and risk-confirmation checks. Starting
the test writes equivalent rules in the existing KeyRecord namespace with the
existing temporary marker and a behavior-test transaction kind. During the test,
the drafts replace the currently managed KeyRecord rules. The encrypted transaction
backup retains the exact pretest configuration, desired mappings and disabled state.
No new hash, frozen contract, baseline or gate is introduced.

The same coordinator keeps an in-memory active session through watcher refreshes.
End, failure report and cancellation restore the pretest configuration. Leaving
the mapping screen requests cancellation, including when start is still pending.
Normal quit waits for cleanup before closing the protected store; failed cleanup
cancels termination and remains visible for retry.
The menu's one-click disable remains available during a test: it first cleans
the temporary rules, then disables the restored permanent mappings if any.
Configuration verification does not record application behavior. A successful user report is transient,
displayed only after cleanup, and does not grant backend qualification.

After a crash or privacy closure, the encrypted journal is recovered when the
target can next be safely reopened. A newly constructed coordinator has no active
session and restores an abandoned test. Locked data, missing targets, unknown
versions and external edits still prevent unsafe writes. External edits are not
automatically merged or overwritten: cleanup remains pending and requires restoring
the known test configuration or the exact pretest configuration before retrying.
An exact manual restoration is recognized without another configuration write.
If access remains unavailable, next-launch cleanup is pending, not claimed complete.

Failures before and after a write are reconciled. Ordinary management operations
cannot discard an unfinished test's recovery state. Cleanup backups retain the
original test transaction across repeated failed retries, and rollback cannot
resurrect temporary rules after a completed test. Production support remains empty.

## Offline verification

Package tests use a simulated configuration port to exercise active refresh,
restoration of permanent and disabled rules, fresh-coordinator crash recovery,
before/after-write failures, journal failure, external edits, repeated cleanup
failures, manual exact restoration, stale preparation, risk confirmation and
read-only refusal. Native tests use temporary files and encrypted fixture stores,
invoke English and Chinese start/end/fail/cancel buttons, close the view, and
close/reopen privacy access. A production-composition test injects host dependencies
and checks that quit is blocked by an external edit, then cleans before shutdown.
The native regression script includes the production quit test in both CI events.

Local validation passed 807 package tests and 109 native regression tests
(89 mapping/file-flow, 18 VIA import, two production-composition cases), plus
unsigned Debug build-for-testing. English and Chinese native screenshots were
captured from temporary configurations; these are not actual Karabiner effects.

Self-review specifically checked preservation of pre-existing disabled rules,
external-edit refusal, temporary-rule resurrection through rollback, journal
retention under repeated cleanup failure and privacy/session invalidation.

Real Karabiner reload, actual shortcut effects, disable latency, devices, Keychain
recovery, uninstall and release qualification remain deferred. Existing deletion
review is retained. Recurring automation remains deleted. This batch stops after
PR checks, authorized merge and main CI.
