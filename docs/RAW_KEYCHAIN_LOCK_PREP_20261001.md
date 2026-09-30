# Raw Keychain read during product lock: preparation

The completed fresh-install and existing-store locked-startup rounds deliberately
made zero guarded product Keychain calls while locked. They cannot establish raw
Security framework behavior. This new opt-in fixture measures that separate gap;
it does not repeat startup, process restart, sleep or performance acceptance.

## Prepared scenario

`HostedProductCompositionTests.testAuthorizedRawKeychainReadWhileProductLocked`
requires `KEYRECORD_HOSTED_RAW_LOCK_TRIAL=1`, a fresh private attempt, valid signed
host evidence and exactly the Keychain/screen operation allowance. It creates a
fixed nonsecret `raw-lock-probe` item and starts the actual product composition
with simulated input, foreground, permission and Secure Input. It saves one
simulated aggregate before reporting readiness for the owner to lock.

After actual lock inputs report locked and the product closes, one raw probe read
runs inside `CounterWindowProductObserver`'s measurement interval. The observer
checks protected reads, publications, aggregates, gate entries and event admission;
the Security-client operation count must increase by exactly the single diagnostic
read. Lock witnesses bracket the interval. Raw status/value-match are observations,
never an unlocked witness; a raw successful read cannot reopen the product.

The owner then unlocks. A fresh unlocked witness and successful probe readback
precede exact cleanup of the probe and product-created items. Raw Security calls
and cleanup run outside MainActor. Values are never printed or persisted outside
Keychain; only status, equality and aggregate/counter outcomes are reported.

## Failure handling

The existing successful-add tracker owns cleanup. A private 0600 record stores
the attempt, UUID seed and successful account names. On scenario failure it retries
that record; if writing still fails, output retains the exact service and successful
account names for inspection. It never expands cleanup to the whole allowlist.

`testAuthorizedRawLockCleanup` can recover a retained, independently authorized
attempt only while unlocked. It validates the record's type, size, mode, attempt,
unique allowed account names and matching service before exact deletion and
absence verification. Unknown/malformed ownership remains blocked for inspection.

The future controller must enforce a single overall deadline, including cleanup;
the fixture's individual waits are not an overall time guarantee. It must retain
the log and ownership files on interruption, detect remaining host processes and
avoid claiming cleanup after a forced exit. No old consumed attempt is reused.

## Verification and next step

Offline cases cover raw read success, raw denial, lost lock witness, malformed
ownership and a failed ownership write followed by successful recording/cleanup.
They use memory Keychain clients and simulated lock signals. Real opt-in cases
remain skipped until a separately coordinated physical window.

The final unsigned hosted build passes. The selected regression run contains
66 cases: 57 passed, nine real opt-ins skipped, zero failures in 7.177 seconds.
Independent source review is CLEAR / APPROVE; its ownership-write failure finding
was repaired and the new regression passes. The private progress file carries only
`waitingForLock` / `waitingForUnlock`; it is an operator cue, not lock evidence or
a successful-result signal.

Build/test logs are `/private/tmp/keyrecord-raw-lock-fixture-build-final.log` and
`/private/tmp/keyrecord-raw-lock-fixture-tests-final.log`; independent review is
`/private/tmp/.omo/evidence/raw-lock-fixture-code-review.md`.

Next: finish offline checks and review, make a bounded signed build using existing
profiles under the owner's standing authorization, and prepare/review the bounded
controller. Request fresh owner readiness only when that preparation is complete.
The owner will only need to lock, wait about 20 seconds and unlock after the explicit
ready signal. No TextEdit input, permission change, sleep or ordinary capture is
needed. This fixture alone does not qualify collecting Release or every privacy/UI
boundary, and no actual raw locked Keychain result is claimed by this document.
