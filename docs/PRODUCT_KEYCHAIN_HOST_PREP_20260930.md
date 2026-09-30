# Product Keychain backend hosted preparation

Status: offline backend integration verified; signed host and actual Keychain
execution remain pending. This is not a lifecycle qualification or permission
to start a system round.

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

## Next prerequisite: one signing configuration attempt

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
