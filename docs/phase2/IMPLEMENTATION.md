# Phase 2 read-only analysis

Scope: current-cycle daily aggregates → deterministic statistics → explanatory recommendation preview. No capture, protected storage, permission, firmware or external configuration access is introduced. Release remains unqualified and fail-closed.

Implementation sequence:
1. Completed: pure analysis module and synthetic rule-boundary tests.
2. Completed: protected snapshots, encrypted layout preferences and bilingual native dashboard implementation.
3. Automated builds and synthetic tests completed. Owner-assisted screenshots and keyboard/VoiceOver smoke checks cover the bounded scenarios in [validation](VALIDATION.md); desktop automation and full visual/accessibility qualification remain unavailable.
4. PR #6 merged as `9da1d24729e3a12883998c90522a77933e7a99b2`; PR #7 merged as `3b9345c30086e9e33c4510047e2692337f5b8643`. Joint review repaired unknown-side display/grouping; PR7 additionally isolates analysis failures and restores live presentation while preserving login-item fields. Earlier screenshots and synthetic tests retain their original candidate boundaries. Current-main bounded input/pause/restart observations are recorded, but complete real-use acceptance remains pending; see [the bounded collaboration record](../CURRENT_MAIN_ACCEPTANCE.md).

Design: preserve exact chord sides and unknown attribution in the domain, merge confirmed left/right/both modifier sides for display, keep unknown sides separately labelled, and retain expandable exact provenance. Ranking uses explicit active-day order, never elapsed wall time. The threshold uses raw cycle counts and distinct dates. All trigger choices are unverified logical previews; no mapping action is available. Missing physical evidence always means logical chord counts. Layout choice is a single existing preference, asked non-modally at the first qualifying dataset, with an explicit skip choice.

User authorization permits autonomous reversible decisions and synthetic-only validation while away. Graphical lock, real keyboard and permission tests require the user's return; no wake, unlock or sleep prevention is authorized.

## Rule choices and limits

`phase2-logical-v1` implements the architecture score: weighted frequency × maximum logical keys saved × source factor × layout factor. Ordinary-source share ≥95% gives 1.0, ≥50% gives 0.75, otherwise 0.5. No preset gives layout factor 0.5; a selected preset gives 0.75. These deliberately conservative deterministic tables are visible in the UI; ordinary observations are not proven authentic and a preset is not a verified physical mapping. Scope concentration is shown separately and controls the 70% default; it is not an extra score multiplier.

Fn unknown yields no trigger preview. Confirmed function keys and simpler command/control/option combinations are sketches only: backend capability/conflict validation is absent, and there is no apply or export action. Stateful shortcuts remain visible in statistics/all candidates with an explicit excluded status and no mapping controls. Unknown application buckets participate in weighted scope denominators. Reset summaries are not analyzed because they do not contain daily/source evidence. No new hashes, snapshots on disk or release gates were added.

The engine accepts the reducer's explicit active-day encounter order. Current storage reconstruction sorts restored day labels, so a clock/date reversal across restart can change ordering; that inherited storage limitation is not repaired by inventing persisted ordinals in this Phase 2 branch. Ordinary chronological datasets reconstruct identically. Full physical geometry/transform evidence and firmware candidate paths remain deferred to qualified backend work.
