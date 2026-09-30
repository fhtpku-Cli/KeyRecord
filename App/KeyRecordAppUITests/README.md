# Native UI test targets

`Phase1FlowTests.swift` contains signed-host XCUITest scenarios using the DEBUG-only
`KEYRECORD_FLOW_FIXTURE` composition, in-memory fakes and temporary persistence.
This is no longer an empty task 18 reservation. Its presence or compilation does
not establish that every scenario ran on a signed host.

`KeyRecordAppTests` separately covers native primitives, accessibility, rendering,
product composition and store/recovery. Hostless execution and explicitly opted-in
real Keychain cases have different effects and evidence scopes. Ordinary CI uses
`Scripts/verify-local.sh --build-only`, skipping App XCTest execution.

The scoped owner-assisted result is recorded in
[the completed walkthrough](../../docs/RELEASE_NATIVE_UI_PREP_20261001.md).
It does not retrospectively mark this entire XCUITest target as executed.
