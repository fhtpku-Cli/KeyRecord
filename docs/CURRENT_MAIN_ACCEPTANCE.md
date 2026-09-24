# Paused-restoration bounded acceptance — 2026-09-24

## Candidate and result

The repaired Debug candidate is based on `3b9345c30086e9e33c4510047e2692337f5b8643`,
with the paused-restoration and flush-diagnostics source/test changes in this branch.
It was rebuilt, copied and development-signed separately for the owner-approved trials.
Before closeout, its saved `source-changes.patch` was compared byte-for-byte with the
repair worktree's complete source/test diff: they matched. These results apply to that
candidate, not unchanged main or Release. No installed application was replaced.

| Round | Observation | Evidence and limit |
| --- | --- | --- |
| Paused restart | Retained target groups were directly visible; three target shortcuts while paused did not change them. | Owner confirmed the checklist. Normal exit 0; instrumented capture/session/aggregate/write counters were all zero. No new screenshot was supplied. |
| Resume, input, normal Quit | Target groups increased from 11/10 to 13/11, combined 21 to 24. | Owner screenshot and report; exit 0. Other input also occurred, so this was not an isolated three-event workload. |
| Second paused restart | Target groups remained 13/11 without Start or Resume. | Owner explicitly confirmed the values and normal Quit; exit 0. All instrumented capture/session/aggregate/write counters were zero. No new screenshot was supplied. |

The collection run recorded **9 issued, 9 returned, 9 successful and 9 durable writes**,
with zero invalidations, failures, timeouts or snapshot-read failures. Its aggregate delta
was 5, consistent with incidental input as well as the target workload. Both paused runs
recorded zero snapshot-read failures. Their publication counter was also zero; that counter
is not rendering evidence for paused restoration. Visible restoration is supported by the
owner's observations, separately from numeric instrumentation.

The two promised repair-specific manual rounds are complete. Both final launches ended
normally, and no further application launch was performed. On 2026-09-24 the owner
separately authorized commit, review, push and merge. That authorization does not start
another live capture trial.

## What changed

Paused startup previously skipped readiness and capture, leaving no restored aggregate and
potentially a privacy-hidden screen. The repair reads encrypted aggregates without starting
capture, verifies privacy before and after the read, checks the protected generation and
current paused preferences, and publishes through the existing protected presentation path.
A paused privacy monitor closes protected state if safety becomes unknown or unavailable.
Read-only restoration does not mark the aggregate dirty or schedule a write.

Flush diagnostics now distinguish physical writer return, successful writer return, durable
acceptance, and invalidation. A successful writer return alone is not durability. These
DEBUG-only counters preserve existing scheduling, cancellation, timeout and storage rules.

For a paused session, the correct menu action is **Resume**. Start follows consent/retry
routing and does not resume paused state. One trial initially used the ambiguous instruction
“Start/resume”; correcting the instruction resolved that step without a menu code change.

## Automated evidence

The accepted source/test patch passed:

- 503 Swift package tests, zero failures.
- 51 selected App tests, zero failures and one native-renderer skip (50 passed).
- Unsigned Debug and universal Release builds.
- Release static boundary inspection: arm64/x86_64, no forbidden diagnostic strings,
  one executable and no helpers. Runtime spawn behavior was not measured.

The package run used a source copy with its scratch directory inside the repository.
An earlier run with an external scratch path failed a capture missing-authorization check
because of the existing safe-directory boundary; that boundary was preserved.
These are the recorded pre-commit measurements of the exact accepted patch. PR CI and
commit-bound closeout reviews provide separate evidence; this document does not predict
their result.

Local evidence roots (excluded from shipping artifacts):

- Repair record: `.omo/repair-20260923/paused-restore-flush/` in the primary repository,
  including red/green regressions, `package-final.log`, `app-final.log`, build logs and
  `release-boundary.log`.
- Signed candidate preparation: `.omo/current-main-acceptance/repaired-20260923/` in the
  acceptance worktree; `source-changes.patch` and `build.log` identify the candidate.
- Opt-in numeric trial summaries: `paused-restart.jyr0cr/`,
  `final-collect-20260924.ajPEEV/` and `final-restart-20260924.Y4wY98/` under that preparation.
- Closeout: `.omo/repair-20260924/paused-closeout/` in the primary repository.

These local logs are not committed or bundled. No real store files, keys, raw input
sequences, event timestamps or unrelated application details are included in this record.

## Historical discrepancy and remaining work

An earlier unrepaired candidate exited normally with **38 issued / 37 durable writes** and
no reported failure or timeout. Old diagnostics did not distinguish all stale-generation
completion outcomes. That is a possible explanation, not an established cause. Neither
data loss nor complete durability for that run is proved; later 9/9 results do not resolve it.
Earlier target-count checks established retention after explicit Resume, while a paused-only
restart displayed hidden content and motivated this repair.

This bounded acceptance does **not** qualify continuous privacy across lock, Secure Input,
foreground or permission transitions; the paused monitor's performance/energy cost;
full recommendation/menu/accessibility behavior; actual dead-session recovery; network
behavior; Intel hardware performance; or signed live Release. Release live capture remains
blocked. See [Phase 1 acceptance](PHASE1_ACCEPTANCE.md) and [project status](PROJECT_STATUS.md).

The next host work should separately measure privacy closure/recovery and monitor cost,
then complete the remaining Phase 1 matrix. Each owner-assisted interval requires concrete
instructions and approval before it starts. Use Resume when paused, preserve initial user
settings, and exit through normal Quit. Do not reset permissions, inspect or copy real
Keychain/store contents, or repeat the already-passed rounds merely for process compliance.
