# Version-scoped lock provider preparation

The existing observed lock algorithm is now shared by Debug and Release source
builds as `ObservedSessionLockProvider`. `SystemSessionLockProvider` remains a
Debug alias for existing fixtures. At this extraction checkpoint Release was
still blocked. Later [integration](RELEASE_CANDIDATE_20261001.md) selected the real
backend/provider on the observed platform and the scoped MVP completed;
unsupported platforms remain closed.

## Evidence and supported candidate

Contract section 4 permits version-scoped observed signals. It does not require
a public-only API. The independent owner-confirmed source observation, signed
fresh locked startup and signed existing-store separate-process restart support
a candidate on native arm64 macOS 27.0, build `26A428`. These existing results are
not repeated or upgraded to general API guarantees.

The default provider checks the exact OS version, build and native architecture.
Any other version/build/architecture, or a failed build query, produces unknown
without registering lock notifications or issuing the live lock queries. Within
the candidate platform, the existing before/console/after eligibility checks,
locked precedence, strict Boolean handling and notification closure are retained.
The console/session fields remain implementation details, not documented atomic
lock-state APIs. No field absence, elapsed time or successful Keychain read is
treated as an unlocked witness.

Release excludes the diagnostic method and Debug protocol. The lifecycle probe's
`ObservedLockSignals.qualifiedLiveVersions` is still empty; extracting this
provider alone did not grant lifecycle or Release qualification. The then-pending
raw lock measurement, privacy/UI and integration subsequently completed within
their [documented scopes](PHASE1_ACCEPTANCE.md). The legacy probe list is not an
instruction to repeat those scenarios.

## Architecture audit

`ruby Scripts/release-boundary.rb bundle-arm64 APP` explicitly checks the Apple
Silicon MVP. The existing `bundle APP` mode still requires both arm64 and x86_64.
Both modes perform identical symbol, resource, entitlement, executable and helper
checks, and report the actual number of architectures scanned. Tests select the
MVP mode only with `T23_RELEASE_SCOPE=apple-silicon-mvp`; unknown scopes fail.

The first 112-case run had one failure because the old default required a
Universal bundle. Its negative bundle cases stopped at that same architecture
failure, so they were not evidence for detecting injected content. The corrected
run must reach each intended rejection before this increment is accepted.

## Verification

- Native arm64 unsigned App Debug and Release builds pass; the hosted probe also
  builds after including the shared source. No App was installed or launched.
- Ruby syntax, source capability audit, explicit ARM bundle audit and static
  product network audit pass. The default Universal mode rejects the ARM-only
  artifact as expected. Static network results are not a live network receipt.
- Hosted offline regression: 59 cases, 52 passed and seven real opt-in cases
  skipped, zero failures. Only memory clients ran; this is not new Keychain data.
- All 112 App isolation, recovery, wiring and Release boundary cases pass in
  76.362 seconds. Negative bundle cases reach their intended token, helper or
  entitlement rejection; the positive ARM bundle passes. The legacy happy-path
  wrapper selector is updated to the renamed positive test.
- Independent final review reports CLEAR / APPROVE with no blockers after
  checking the completed logs and the synchronized wrapper selector.

Logs are under `/private/tmp/keyrecord-observed-lock-*`: Debug/Release build logs,
`probe-tests.log` and `app-tests-final.log`. Build products are in the separate
`keyrecord-observed-lock-20261001-debug` and `-release` directories. The extraction
review is `/private/tmp/.omo/evidence/observed-lock-extraction-code-review.md`.
