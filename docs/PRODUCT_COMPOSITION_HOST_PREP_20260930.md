# Full product composition in the Keychain probe

## Result and boundary

The existing `KeychainLifecycleTests` target now compiles the actual App sources,
including `ProductComposition`, and links Core, Capture, Store and Analysis.
It also compiles `CounterWindowProductObserver`. The probe keeps its passive host
entry point and existing host/test bundle identities; the App delegate is not
included. No production source or collecting Release policy changed.

`HostedProductCompositionTests` assembles the real lifecycle, capture coordinator,
reduction, encrypted store and UI model. Input, permission, lock, Secure Input,
foreground, login item, notifications and termination are explicitly simulated.
The same scenario can use the App Keychain backend with either an in-memory
Security client or the existing per-operation signed authorization client.

The offline scenario passed: consent and startup, two fixed bare-key inputs,
encrypted save/readback of two, simulated lock closure, rejected input while
closed, zero protected-read/publication/aggregate deltas in bounded lock and
unlock windows, explicit recovery, and a new composition/store reading two then
saving a third count. The reopen occurs in the same process. It is not a process
restart, a real OS lock transition, rendered-pixel evidence or lock qualification.

The real Keychain variant is prepared but has not run. It requires its own opt-in
and the existing signed manifest authorizing only test-item Keychain operations.
It uses a new probe service and a private store under that round's directory.
Successful Keychain creates are tracked at the client boundary, including metadata;
cleanup deletes and verifies absence only for those owned accounts, even if the
product scenario fails. A duplicate/preexisting-item regression verifies such
items are not owned or deleted. A cleanup failure fails the test and retains the
service record for follow-up. No key bytes are logged.

## Verification

- Unsigned native arm64 Debug and Release probe test builds pass.
- Direct hostless XCTest selects 18 cases: 16 offline cases pass, zero failures,
  and both real Keychain opt-in cases skip. The new complete product scenario
  takes 0.268 seconds with the memory client.
- The lifecycle package selects 139 cases: 138 pass, zero failures and one
  read-only signed-file fixture test skips because no fixture was supplied.
- Existing Security API deprecation and Xcode headermap warnings remain.
  The initial Swift actor-isolation error and missing shared view dependency were
  corrected; both failed build logs remain distinct from the final passing build.

Logs under `/private/tmp`:

- `keyrecord-product-composition-build-linked.log`
- `keyrecord-product-composition-release-build.log`
- `keyrecord-product-composition-tests.log`
- `keyrecord-product-composition-lifecycle-tests.log`

## Next bounded round

After fresh approval, build the candidate with the existing probe profiles and
certificate, without provisioning updates, installation or input capture. Then
run only `testAuthorizedProductCompositionWithRealKeychainAndSimulatedInput` in
the signed host with a fresh private namespace/store. The owner need only remain
logged in and unlocked; no keys, permissions, lock or sleep actions are required.
The two stages have separate two-minute bounds and stop on signing, authentication,
Keychain or test errors. Inspect the exact xcresult test and final host absence;
exit zero alone is not a passing result.

This would establish full product persistence/recovery with a real unlocked
Keychain and simulated privacy signals. Independent OS lock authority,
locked-state Keychain behavior, actual process restart under lock and collecting
Release remain separate open requirements. Previously completed physical input,
sleep and ARM performance trials are not repeated by this work.
