# Apple Silicon collecting candidate

Status: product Release dependencies are connected and pass offline validation.
The integrated Release has not yet been signed, installed or exercised with real
input. Public distribution and PR merge remain outside this work.

The Release composition uses the same exact-item Security backend and query
builders already measured in the signed product cases. Only its DEBUG read
instrumentation remains conditional. Non-synchronizable data-protection items,
device-only accessibility, authentication-UI refusal, exact account queries and
all product privacy/recovery checks remain intact.

Immutable capture qualification permits only the existing observed native arm64
macOS 27.0 build 26A428 candidate. Unsupported platform reads select the blocked
backend and an unknown lock provider. Release has no developer environment/defaults
arming path. The same observed provider reaches product readiness and the event
source, including synchronous notification closure and stale-startup rejection.

Default Keychain namespace and App Support directory derive from the same validated
Bundle ID. Missing, empty, malformed and path-traversal identities are rejected;
there is no fallback to `com.keyrecord.app`. That ordinary app identity retains its
original location. Explicit DEBUG trial selection still excludes the fixed daily
`com.keyrecord.app/store` path and its parent/child overlaps independently of the
trial's own default identity.

Validation: native arm64 unsigned Debug and Release builds pass; 127 selected App
tests pass in 75.322 seconds, including factory support/identity isolation, malformed
identity refusal, daily-root exclusion, exact Keychain query properties, recovery
and destructive Release capability mutations. Six core trial-isolation tests pass.
The actual Release project/bundle audit reports one executable, no helpers or
forbidden developer/test tokens; the static network audit reports zero matches.
The audit now permits the two deliberately promoted Keychain implementation types;
all other restrictions and the default Universal architecture mode remain intact.

Build/test logs: `/private/tmp/keyrecord-release-integration-debug-build.log`,
`/private/tmp/keyrecord-release-integration-release-build.log`,
`/private/tmp/keyrecord-release-integration-app-tests.log` and
`/private/tmp/keyrecord-release-integration-trial-isolation-tests.log`.

The MVP surface now uses the existing Phase 1 aggregate view. Recommendation
controls, menu suffix and badge are absent; Phase 2 implementation is retained.
Ten focused native UI/modifier tests pass, including real ProductScreens tab
activation, English/Chinese totals and removal of all rows when the snapshot is
cleared. Both rendered locale images were inspected. These use synthetic data,
not live capture. The view labels keys numerically and applications by Bundle ID.
Debug/Release builds and the final Release static audits pass again.

Native evidence: `/private/tmp/keyrecord-mvp-surface-native-final.log` and
`/private/tmp/keyrecord-mvp-ui-output/product-aggregates-{en,zh-Hans}.png`.
An initial unchanged window-teardown test threw an AppKit transition exception;
it passed subsequent runs without a product change. New test fixture corrections
select the native window toolbar tab, set the requested locale and give only the
test screenshot an opaque background. Assertions retain actual before/after UI
postconditions rather than relying on AXPress's inaccurate return status.

Next: prepare a signed isolated Release using existing signing material. Reusing
an older trial Bundle ID also reuses its Keychain namespace, so an empty store
must not be assumed safe or fresh. Resolve the exact isolated identity/store pair
before installation. Stop for owner readiness
before a short real-input/UI check. Do not repeat completed physical lock, sleep,
short performance or FR-P7 rounds solely for dependency selection.
