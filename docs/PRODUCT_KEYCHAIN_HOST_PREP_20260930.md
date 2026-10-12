# Product Keychain backend hosted preparation

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round. Subsequent [product composition](PRODUCT_COMPOSITION_ROUND_20260930.md), [locked restart](PRODUCT_LOCKED_RESTART_PREP_20261001.md) and [Release integration](RELEASE_CANDIDATE_20261001.md) supersede then-open follow-up items, within their own evidence scopes.

Status: the separately approved [real Keychain round](PRODUCT_KEYCHAIN_ROUND_20260930.md)
on signed `25ef0f117` passed one actual test with no failures/skips, including exact
test-item cleanup; the host exited normally. Full product privacy/recovery and
locked-state qualification remain open. Preparation and signing history follow.

## Bounded execution preparation

This section records preparation before the subsequent approved round linked above.

The private controller `/private/tmp/keyrecord-product-keychain-round.py` and
AppKit helper `/private/tmp/KeyRecordProbeControl` are prepared for the existing
signed `25ef0f117` artifact. The helper compiles with Swift 6 and binds process
inspection/termination to the exact probe bundle and executable paths. Its
read-only inspection found no probe instances. The controller's `--check` passed
without launching a host, writing a manifest or calling Keychain CRUD.

Synthetic controller checks passed for success, nonzero exit, timeout, forced
termination, unavailable host observation and a failing log writer. Unknown
process state remains an error. These checks use disposable child processes and
fake host callbacks, not the signed host or Security item operations.

After separate approval, the controller will reuse the existing manifest schema
and enable only `testAuthorizedIsolatedProductKeychainLifecycle` with Keychain-only
operations in the existing private signing directory. It requests shutdown at
85 seconds, escalates at 90 seconds, and reserves cleanup time within a proposed
two-minute round. XCTest has a 70-second test allowance; extra Xcode diagnostic
collection is disabled. Normal completion still requires checking the xcresult
summary and exact test node: one executed passing test, no skips/failures, and
no remaining host. Exit zero alone is insufficient. Use `xcresulttool get
test-results summary` and `test-results tests` against `keychain.xcresult`.
The test verifies deletion of every item it created before returning success;
interrupted/failed cleanup retains the scoped service record for follow-up.

No live manifest or run outputs exist yet. No installation or additional signing
is needed. The owner need only remain logged in and unlocked during the proposed
round; no keyboard input, permission toggle, screen lock or sleep is involved.
Actual CRUD, locked-state protection and full product recovery remain unverified.
Both CI runs for `25ef0f117` (36698676154 / 36698671693) and the subsequent
documentation commit `df7f7450b` (36699242951 / 36699238880) succeeded.

## Approved repaired signing result

The owner separately approved one two-minute rebuild of `25ef0f117` using only
the existing profiles/certificate. The clean source was verified as
`25ef0f117f9ee5d61c66cc78928f31efe1baabbc`. Xcode completed `build-for-testing`
in 16.86 seconds with exit zero. The command omitted `-allowProvisioningUpdates`;
no new signing materials were requested. No installation, host launch or Keychain
test occurred. This second bounded authorization is consumed.

Artifacts are under
`/private/tmp/keyrecord-product-keychain-signing-fixed-20260930`, with `build.log`,
`result.json`, and `build/lifecycle/Build/Products/Debug/KeychainLifecycleProbe.app`.
The driver is `/private/tmp/keyrecord-bounded-signing-fixed-20260930.py`.
Both strict disk signatures verify. The host has its exact application identity
and Keychain group; the test plug-in has no independent entitlements, as expected.
The embedded profile UUIDs remain `01e3da0d-8706-4ed6-8234-4747a5bf9b9d` (host)
and `a623bdf3-3bb1-4b5b-b03b-c0e89cf905b4` (tests), matching the first signing run.

The actual repaired `LivePreflight.signature` code inspected this new signed host
and plug-in from a separate read-only test runner: one selected case passed with
zero failures/skips, checking both roles, policy, identifiers and matching
team/certificate. Log: `/private/tmp/keyrecord-fixed-signed-inspection.log`.
This executes static inspection, not the signed host or its Keychain test. The
complete manifest/controller preflight and live Security CRUD remain unrun.
The bounded controller is now prepared as recorded above. Approval of the real
isolated Keychain round remains required; the signed rebuild itself is complete.

## Approved signing result and follow-up

The owner approved the exact two-minute signing configuration attempt on
2026-09-30. The bounded controller ran once, for 25.06 seconds, exiting zero.
Xcode obtained matching Mac development profiles for both probe identities and
built source `b889640b458e2de7ce2b942f0b2c6758ab447b8a`. The source worktree was
clean and matched that revision before the command. No login/payment prompt or
build signing error appeared. No installation, host launch, capture, or test-item
Keychain operation occurred. This one attempt is consumed.

Artifacts are retained under
`/private/tmp/keyrecord-product-keychain-signing-20260930`: `result.json`,
`build.log`, and `build/lifecycle/Build/Products/Debug/KeychainLifecycleProbe.app`.
The bounded driver is `/private/tmp/keyrecord-bounded-signing-20260930.py`.
Both host and nested test bundle pass strict disk signature verification and have
matching team/certificate identities. Embedded profiles match their respective
application identifiers and team `P3W62C39TN`; both expire on 2026-10-07 UTC.
The host claims the exact application/team identity and single expected Keychain
access group. The test bundle has no executable entitlement dictionary.

The existing preflight incorrectly required process entitlements on both the host
and its in-process test plug-in. Apple's [signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
places entitlements on main executables, not library code; the
[Hardened Runtime documentation](https://developer.apple.com/documentation/security/hardened-runtime)
states that in-process plug-ins use their host's entitlements. Actual `otool -hv`
inspection reports `EXECUTE` for the host and `BUNDLE` for the test executable.
A read-only regression against these exact signed files failed on the original
plug-in entitlement assertion before the repair.

The corrected `LivePreflight.signature` checks the signed executable's Mach-O
role as well as its identity: the host must be `EXECUTE` with the existing exact
Keychain entitlements; the test plug-in must be `BUNDLE` with no independent
entitlement claims. All parsed slices must agree, and missing/malformed headers
are rejected. Strict signatures, matching teams/certificates, exact host/test
identities, running-host binding, manifest authorization and per-operation checks
remain mandatory. The new checks do not authorize a different executable to use
the plug-in exemption.

With the signed files supplied as a read-only fixture, all 139 lifecycle cases
pass without skips, including missing/wrong host entitlements, non-bundle plug-ins
and mixed/malformed code headers. The compiled Xcode selection passes 33 cases;
unsigned hosted Debug and Release test builds also pass. Logs:
`/private/tmp/keyrecord-hosted-entitlements-{red,green,build,release-build,compiled-tests}.log`.
Without an explicit signed disk fixture, only that new optional inspection test
skips; this is not a real Keychain trial. Both CI runs for `b889640b4` passed:
36696769046 / 36696761909. Those CI results precede this follow-up repair.

The original signed artifact is preserved unchanged. Before any real Keychain
round, the repaired test code needs a separately authorized signed rebuild using
the now-existing profiles and a bounded execution controller. No second signing
attempt or launch follows automatically from the first approval.

## Implementation

The hosted Debug test target now compiles the App's `LocalKeychainBackend` and
`LocalKeychainQueries` sources and links the actual Core/Store packages. The
backend defaults to the same Security calls through `SystemLocalKeychainClient`;
an injected client permits offline checks and per-operation hosted authorization.
The backend's status mapping, exact-item inventory, metadata conflict handling
and protected-read observation are retained.

`AuthorizedProductKeychainClient` recomputes the existing signed authorization
before each operation. It requires exact trial service/accounts, data-protection
Keychain, no synchronization and no authentication UI. Adds retain the device-only
policy. Updates cannot change identity or weaken that policy. Tests verify that
expiry between calls prevents the next dispatch. No new manifest or gate is added.
An authorized attempt counts as a protected-read attempt even if authorization
prevents the Security call; this counter is not an exact syscall count.

The opt-in test is
`HostedProductKeychainBackendTests/testAuthorizedIsolatedProductKeychainLifecycle`.
It requires `KEYRECORD_HOSTED_PRODUCT_KEYCHAIN_TRIAL=1`, `PHASE1_QA_ATTEMPT`, and the
existing valid signed host manifest with only the Keychain operation authorized.
Without the opt-in it skips; the offline invocation explicitly excludes this test.

Within a fresh service it checks absence, creates two keys and metadata, compares
readback, updates metadata, checks the exact version inventory and protection
attributes, deletes an item and checks absence. A fresh backend object rereads
metadata; this is **not process restart evidence or a complete key rotation**.
The normal sequence makes 24 exact Security calls, including cleanup. Mismatches
throw immediately into cleanup. Only successfully created items are tracked for
deletion; repeated deletion is idempotent. Every cleanup call is also authorized.
If cleanup cannot finish, the private service record is retained for follow-up;
no key bytes are written to that record or assertion messages.

The new backend tests and adapter are Debug-only, matching the current product
backend. Existing query tests remain available in Release. The main product
Release still excludes this backend and retains its existing capture restrictions.

## Verification

- Offline lifecycle SwiftPM suites: 135 cases (12 observer, 40 scenario, 83
  preflight), zero failures.
- Compiled hosted Debug selection: 14 cases (four authorization/backend tests and
  ten shared query/backend tests), zero failures or skips; no Security CRUD calls.
- Main App selection: ten backend/query plus all 63 recovery/quit cases, zero
  failures or skips. Host boundaries in recovery tests remain simulated.
- Six project/Release configuration tests and 18 package boundary/privacy cases
  pass. No Universal-only test is claimed for the native artifact.
- Hosted Debug and Release test builds, main Debug test build and unsigned arm64
  product Release build succeed. Existing deprecation/headermap warnings remain.
- The final executable network audit reports zero matches. `nm` and `strings`
  contain none of the new backend-client/hosted-test identifiers. The first audit
  invocation passed an App directory rather than an executable and correctly
  failed; it is retained separately and is not counted as successful validation.

Logs are under `/private/tmp/keyrecord-product-keychain-`: `package.log`,
`host-build.log`, `host-release.log`, `host-tests.log`, `app-build.log`,
`app-tests.log`, `isolation.log`, `boundaries.log`, `release.log`,
`release-audit.log` (wrong argument) and `release-executable-audit.log` (correct).
Prior observer head `e9f04562e` also has successful PR/push CI runs
36693846706 / 36693841757; these do not qualify this subsequent increment.

## Original signing preparation (completed above)

Read-only inventory on 2026-09-30 found two installed profiles for team
`P3W62C39TN`, matching only `com.keyrecord.trial.mvp20260929` and
`com.keyrecord.trial.performance.mvp20260929`. Neither matches the probe host
`com.keyrecord.phase1.probe.host` or test bundle `com.keyrecord.phase1.probe.tests`.
No signing, account operation or Keychain mutation was performed.

The prepared entitlement template at
`Spikes/KeychainLifecycle/Config/ProductKeychainProbe.entitlements` supplies the
same application/team/group requirements already checked by `LivePreflight`.
It is not enabled in the main product project. For the separately authorized
Debug probe build, use the existing team with Xcode automatic signing and
`CODE_SIGN_ENTITLEMENTS=Config/ProductKeychainProbe.entitlements`. Xcode must obtain
profiles that authorize both identities and the exact host Keychain access group;
do not re-sign a profile-less bundle or reuse either trial profile.

The proposed next action is **build only**, capped at two minutes: use the existing
Xcode account to obtain/create matching development profiles and build the arm64
Debug host/test bundle in a fresh private attempt directory. Stop on login,
subscription/payment, authentication, or signing error. Do not install, launch,
start input capture, access trial statistics or run the opt-in Keychain test.
After successful signing, verify the actual profiles/signatures and prepare the
bounded execution controller before requesting the separate Keychain round.

Full product lock observation, independent system-state authority, missing-key
product recovery and a collecting Release remain separate unfinished work.
