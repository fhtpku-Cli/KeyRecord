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

## Desktop automation limitation

Computer-use inspection failed with `Sky Computer Use native pipe closed before response`, and later exact-app-path retries returned `-10005 timeoutReached`. No assistant AX tree, screenshot or click was obtained. Owner-provided screenshots and explicit interaction feedback now supply the scoped manual evidence below. No wake, unlock, sleep prevention, TCC change, real input capture or external remap was attempted. A successful build or bitmap render does not establish interactive acceptance.

Both attempted offscreen capture methods also failed visual inspection: NSView caching produced mostly black images; SwiftUI ImageRenderer produced a blank white dashboard. The render test now checks for content and reports SKIPPED when absent. Image file creation/size alone is not counted as a rendering pass. Images remain local under /tmp and are not presented as UI evidence.

## Earlier automated checks observed (before UI follow-up)

- Pure Swift targeted suite: 28 tests passed (12 analysis, 3 layout, 7 lifecycle boundaries, 6 product/module boundaries). Log: `/tmp/keyrecord-phase2-targeted-final.log`.
- SwiftPM Release build passed: `/tmp/keyrecord-phase2-swift-release-final.log`.
- Unsigned Xcode universal Release build passed: `/tmp/keyrecord-phase2-release.log`; this is compilation only, not ARM/Intel execution or release qualification.
- Synthetic App integration: privacy clearing, layout success/failure, exact-side display merge, protected reduction read all passed. Offscreen render is unavailable and must be reported as skipped.
- Full sandbox Swift run encountered process/cache/file-access failures and an old module allowlist expectation; the module expectation was corrected and targeted structural checks passed. Performance probe reported `translatedHost` under sandbox. This does not diagnose actual translation or qualify performance.
- Automatic approval rejected an elevated full Swift suite because it includes capture/system-level tests. That action was not retried indirectly. Only explicitly isolated pure test classes were subsequently run with elevation.
- Full hostless App suite was stopped during existing `PrimitiveStateTests.testFailureStressMatrix`, with desktop unavailable. Its old module-list assertion was updated for the new target; the aborted suite is not a pass.


## Owner-assisted UI follow-up — 2026-09-22

The owner approved synthetic-only preview runs. Screenshots and chronological observations are retained locally in the main checkout under `.omo/repair-20260922/phase2-ui-validation/` (`RUN.md`, screenshots01–12). They contain fixed synthetic fixtures, not real captured statistics.

| Evidence | Observed result | Scope |
| --- | --- | --- |
| Screenshots01–02 | English populated view, Chinese factors and exact modifier details rendered | Before follow-up changes; sampled visible cards |
| Screenshots03–04 | ANSI changed layout factor0.50→0.75 and score21.47→32.20;44 uses/2days unchanged; Global selection visible | Synthetic in-memory interaction, not real preference persistence |
| Screenshots05–06 | 8-use observation, Cmd-Tab exclusion and unknown-application explanation | Before follow-up changes |
| Screenshots07–09 | Explicit empty state, hidden details, populated restoration and narrow-card wrapping | Before follow-up changes; no AX non-disclosure claim |
| Screenshots10–11 | Revised toolbar labels fully visible and no-trigger card says sample threshold met | Current follow-up build, supplied narrow viewport; vertical fallback not observed |
| Screenshot12 | Dark no-trigger card and expanded factors visually readable; long paragraphs wrap | Current follow-up build, one Chinese viewport; no quantitative contrast measurement |
| Owner keyboard report | Tab/Shift-Tab navigation and Space activation worked after enabling macOS Keyboard navigation | Before follow-up changes; initial apparent failure occurred with the system setting off |
| Owner VoiceOver report | Candidate names/counts read and factors disclosure activated using the instructed shortcut | Current follow-up build; owner explicitly distinguished this from merely enabling VoiceOver |

Follow-up implementation relabels eligibility as meeting the sample threshold, explains that this does not guarantee a simpler trigger, uses neutral empty-list copy, and adapts native preview pickers to available width. It does not change analysis scoring, collection, persistence or privacy logic.

Current ARM Debug build-for-testing passed, and four explicitly selected non-graphical `AnalysisFlowTests` passed with zero failures: privacy clearing/fresh publication, temporary-fixture layout persistence and save failure, protected-generation reduction, and exact-side display counts. Both locale catalogs passed `plutil -lint`, and `git diff --check` passed. Logs: `followup-build.log`, `followup-tests.log` in the local evidence directory. The first build command mixed app x86_64 compilation with arm64 package dependencies and failed; the local-preview retry set `ARCHS=arm64` explicitly without changing release settings. No fresh universal Release qualification is claimed.

Remaining qualification: the full locale × size × appearance matrix, large text, all keyboard controls and screen-reader order, hidden-state AX non-disclosure, and the preview's vertical fallback have not been verified. Earlier screenshot evidence must not be relabelled as fresh current-build evidence. The no-trigger factors row still describes zero saved keys as the first preview despite no generated trigger; this is a minor wording follow-up, not a positive savings claim. Basic owner-assisted checks do not constitute full accessibility, G2 or Release acceptance.


## Unknown modifier side repair — 2026-09-22

Joint PR5/PR6 review found that the default formatter omitted the unknown-side marker and the statistics grouping merged unknown sides with known sides, contrary to architecture §4.5. The repair reuses the existing localized marker and keeps unknown groups separate; confirmed left/right/both still merge. Stored identities/counts, ranking, capture and preference behavior are unchanged.

Two new regressions failed before the fix: the fixture produced2 groups rather than3 and unknown totals were combined with known sides; all four modifier families lacked their default unknown labels in both locales. After the fix, six selected non-graphical AnalysisFlow tests passed. The isolated combined PR5/PR6 build with the same source repair also passed15 selected App analysis/reduction tests. These bounded synthetic runs do not qualify a live host.

The owner explicitly approved launching the repaired combined Debug preview with only KEYRECORD_ANALYSIS_PREVIEW=1 in a clean environment. Fresh owner captures confirm the Chinese frequent-statistics Z row shows 命令（侧别未知） and20 uses, and the English candidate Z card shows Command (side unknown),20 raw uses across2 local days, separately marks Fn state unknown, and exposes no mapping action. These are two distinct visible regions, not the full bilingual surface matrix. The same-key known/unknown separation is proven by the regression fixture, not by a paired row in these screenshots. Evidence is retained locally under `.omo/repair-20260922/integration-review/` in the main checkout: `side-zh-statistics.png`, `side-en-candidate.png`, `side-red-tests.log`, `side-green-tests.log`, `integrated-fix-tests.log`. No assistant-driven AX interaction or fresh VoiceOver claim is made.

## Cursor pulse-publication follow-up (2026-09-22)

PR #6 review identified two composition defects: an analysis-only error escaped to the
pulse's protected shutdown handler, and a dead collecting session could republish
statistics after `sync()` had hidden them. Publication now checks lifecycle visibility
and capture liveness before reading either snapshot; paused sessions still retain their
statistics. Only `AnalysisError` is downgraded to an unavailable preview. Key-gate,
stale-generation, snapshot-read and other errors still propagate to the existing pulse
shutdown handler. The synchronous refresh uses the same analysis-error policy.

The production publication step was extracted without fixing its behavior first. Four
synthetic runtime tests then produced eight failed assertions in the two reported paths;
healthy publication and key-closure propagation already passed. After the repair, eight
publication tests plus six existing analysis-flow and nine reduction tests passed (23
total). Coverage includes real analysis validation failure on a synthetic misclassified
row, repeated dead-session ticks, healthy recovery, paused statistics, privacy closure,
and gate/read errors. Debug App and test-target compilation passed.

These are direct executions of the production publication function with real in-memory
lifecycle/reduction/analysis objects. They do not instantiate the full App composition,
run the one-second timer or OS capture, inspect the physical menu-bar badge, or qualify
real Keychain/privacy/Release behavior. No owner data or system setting was changed.

PR #7 follow-up: a dead refresh could reset the displayed login-item setting and
leave the UI blocked after the recovery coordinator had already refreshed its
cached liveness. Two regression tests reproduced five assertion failures.
Publication now mirrors current lifecycle state on every refresh, and the shared
blocked presentation operation clears content without changing login-item fields.
The recovery test no longer manually synchronizes the flow before asserting a
live refresh. All 24 selected synthetic tests passed, including nine publication
cases. This remains publication-level runtime evidence, not a live timer or OS
login-item registration test.
