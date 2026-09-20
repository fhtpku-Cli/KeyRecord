# KeyRecord

KeyRecord is an in-development native macOS menu-bar app for local, aggregate keyboard-use statistics. It aims to count shortcuts by application and bare keys without storing typed text or event sequences. The codebase uses Swift 6, macOS 14+, and Apple system frameworks.

**Current stage: Phase 1 integration repair and bounded DEBUG validation.** Passing package tests or compiling an App does not establish reliable daily use, full G1 acceptance, or release readiness. Release capture remains blocked pending host qualification. Owner-approved bounded signed Debug runs observed physical input, attribution to the tested application, displayed increments and retention after normal quit/restart. This qualifies only that observed scenario on one host; formal signed lifecycle, lock/keychain, UI/accessibility, ARM/Intel performance and network qualification remain separate. See [current status](docs/PROJECT_STATUS.md) for measured results and their limits.

## Build and test

Use a Mac with full Xcode selected as the developer toolchain and Swift 6.2 or newer (the code uses `isolated deinit`). Run from a clone:

```sh
Scripts/verify-local.sh
```

The script runs, in order:

1. `swift test` for Core, Capture, Store and Integration.
2. `swift build -c release` for SwiftPM targets.
3. An unsigned universal (`arm64 x86_64`) Release App build in a fresh directory.
4. A native-architecture Debug `build-for-testing`.
5. Hostless `xcrun xctest`, supplying `T23_RELEASE_APP` as the absolute path to that exact newly built universal Release App.

Each invocation retains logs and Xcode products under `.build/verification/run.*`; App test screenshots/artifacts go into that invocation’s `qa/` directory via `KEYRECORD_QA_OUTPUT_DIR`. It stops on failure, so later steps may not have run. Do not run concurrent verification against the shared SwiftPM build directory. App XCTest is separate from `swift test`; AppKit/accessibility checks need a suitable logged-in graphical session. A host limitation, failed assertion or skip is not a pass.

For a headless runner:

```sh
Scripts/verify-local.sh --build-only
```

This still runs SwiftPM tests and both App builds, but deliberately skips App XCTest. The ordinary [macOS CI workflow](.github/workflows/macos.yml) uses this mode. The workflow explicitly selects `/Applications/Xcode_26.3.app/Contents/Developer`, listed in the [official macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md); [Swift 6.2.4 ships in Xcode 26.3](https://forums.swift.org/t/announcing-swift-6-2-4/85050). The local review/repair host uses Xcode 27.0 (27A266a), Apple Swift 6.4; CI passed at `b46316bbb` with Xcode 26.3. Later checks are revision-specific: consult the PR checks for the current commit; older CI or local results do not establish current remote compatibility. A green CI run proves only those tests and unsigned compilation. It does not launch capture, exercise WindowServer/VoiceOver, validate Intel execution, prove signing/notarization, or authorize host operations.

## Scope and host validation

The portable implementation specification is [PHASE1_CONTRACT.md](docs/PHASE1_CONTRACT.md), with [PRD](docs/PRD.md) and [technical architecture](docs/TECHNICAL_ARCHITECTURE.md). No local `.omo` plan is needed to understand the behavioral contract or run ordinary verification. Historical evidence and its existing qualification procedures remain separate from these developer checks.

A human-assisted live run must identify the exact Debug App, ensure only one instance, use an explicitly approved store and small set of test shortcuts, and stop automatically after 30–60 seconds. Observe only aggregate counters and closed states. Check A→B attribution with unflushed counts, exclusion/unexclude, pause/resume, Off→On, durable completion and process restart. Lock/unlock, sleep/wake, permission changes and key unavailability require their explicit host-operation scope and existing prerequisites; do not reset TCC, remove real keys or infer authorization from a successful build. Unknown privacy/lock state must stay closed, and waking must respect user pause.

No runtime result is claimed by these instructions. Harness results cannot substitute for the real product pipeline. Lock or crash can lose all statistics since the last completed durable save; the one-second flush cadence is a scheduling target, not a bounded-loss guarantee. Macro recommendations/mapping, FR-P6 full password backup and public release remain later, independently qualified work.

## Repository layout

- `Sources/`, `Tests/`: SwiftPM libraries and tests.
- `App/`, `KeyRecord.xcodeproj`: native product and App XCTest.
- `docs/`: product specification, architecture and status.
- `Scripts/`: development checks and existing qualification workflows.
- `Spikes/`, `evidence/phase0/`: historical experiments and evidence; preserve their original meaning and contents.
