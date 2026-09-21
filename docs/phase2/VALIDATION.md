# Phase 2 validation

This is a read-only Debug prototype, not Phase 1 acceptance or Release qualification.

## Synthetic-only reproduction

Build `KeyRecordApp` Debug with Xcode. Launch its executable with a clean environment and `KEYRECORD_ANALYSIS_PREVIEW=1`. This DEBUG-only entry returns before ProductComposition, real capture, preferences, store or keychain initialization. Do not set `KEYRECORD_LOCAL_CAPTURE`.

The preview contains only fixed aggregate fixtures. Use the language picker and populated/empty/hidden picker. Choose ANSI/ISO/Alice/Split or skip; expand factors and sided provenance; toggle all candidates; select global/top application. Changes in this isolated preview remain in memory. The production layout action separately uses existing encrypted preference transactions.

Run `swift test --disable-sandbox`, and build-for-testing the Xcode scheme; run hostless `AnalysisFlowTests` using `xcrun xctest -XCTest AnalysisFlowTests <test bundle>`. Set `KEYRECORD_QA_OUTPUT_DIR` to a disposable directory for six synthetic native-render images. These are in-process render tests, not proof of physical keyboard, VoiceOver or real session-lock behavior.

## User-return manual checklist

- Open only the synthetic preview; do not start real capture.
- Verify English and Chinese at 1000×700 and 640×480, light/dark appearance, and large text.
- Tab/Shift-Tab through layout buttons, candidate toggle, disclosure controls and scope radios; activate with Space/Return. Read key statuses and counts with VoiceOver.
- Confirm Top 5 versus all candidates, 8-use observation, Cmd-Tab exclusion, unknown application disabled scope, Fn-unknown no-trigger explanation, suspected-source factors.
- Pick a layout and confirm the question disappears; choose skip and confirm the same. Production persistence is covered by isolated preference tests, not real-keychain observation.
- Switch to hidden and confirm no statistics/candidates remain, then empty and confirm explicit empty messaging.

## Current graphical limitation

Computer-use inspection failed twice with `Sky Computer Use native pipe closed before response`. No screen contents or lock state were obtained. No wake, unlock, sleep prevention, TCC change, real input capture or external remap was attempted. Interactive UI and VoiceOver validation remain pending; a successful build or bitmap render does not clear this gap.

Both attempted offscreen capture methods also failed visual inspection: NSView caching produced mostly black images; SwiftUI ImageRenderer produced a blank white dashboard. The render test now checks for content and reports SKIPPED when absent. Image file creation/size alone is not counted as a rendering pass. Images remain local under /tmp and are not presented as UI evidence.

## Automated checks observed

- Pure Swift targeted suite: 28 tests passed (12 analysis, 3 layout, 7 lifecycle boundaries, 6 product/module boundaries). Log: `/tmp/keyrecord-phase2-targeted-final.log`.
- SwiftPM Release build passed: `/tmp/keyrecord-phase2-swift-release-final.log`.
- Unsigned Xcode universal Release build passed: `/tmp/keyrecord-phase2-release.log`; this is compilation only, not ARM/Intel execution or release qualification.
- Synthetic App integration: privacy clearing, layout success/failure, exact-side display merge, protected reduction read all passed. Offscreen render is unavailable and must be reported as skipped.
- Full sandbox Swift run encountered process/cache/file-access failures and an old module allowlist expectation; the module expectation was corrected and targeted structural checks passed. Performance probe reported `translatedHost` under sandbox. This does not diagnose actual translation or qualify performance.
- Automatic approval rejected an elevated full Swift suite because it includes capture/system-level tests. That action was not retried indirectly. Only explicitly isolated pure test classes were subsequently run with elevation.
- Full hostless App suite was stopped during existing `PrimitiveStateTests.testFailureStressMatrix`, with desktop unavailable. Its old module-list assertion was updated for the new target; the aborted suite is not a pass.
