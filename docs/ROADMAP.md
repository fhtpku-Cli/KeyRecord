# Roadmap and current delivery status

Status date: 2026-10-01, Asia/Shanghai. Current main product merge:
`8bb99e81a6ea411c5e167e156a548372e961c44d` ([PR #17](https://github.com/fhtpku-Cli/KeyRecord/pull/17)).
Merge-commit [CI passed](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36768522338).
This page reconciles the existing architecture §15 roadmap; it adds no gate,
baseline, product requirement, feature implementation or host authorization.

## Phase status

| Phase | Current state | Remaining scope / evidence boundary |
|---|---|---|
| Phase 0: feasibility | Capture prerequisites progressed beyond the old G0 OPEN writeback; historical artifacts remain unchanged | Karabiner version/reload/disable latency, VIA protocol/dialect/importer, Vial importer/live capture and backup KDF/Intel evidence retain their own limits. Phase 0 is not globally all-green. |
| Phase 1: collection, privacy, encrypted storage | **Approved Apple Silicon MVP complete and merged** | Measured arm64 macOS 27.0 build 26A428 only; development-signed local trial. Existing candidate-specific short ARM and lifecycle evidence retained. Full original G1/v1, all OS/architectures and public release are not claimed. |
| Phase 2: deterministic analysis | **Prototype implemented; full FR-R/FR-E and G2 incomplete** | Pure logical engine, protected publication and native dashboard prototype exist. ProductScreens currently uses Phase 1 aggregates. Product integration, remaining native prototype coverage, physical-evidence paths and backend-aware candidate constraints need explicit completion. |
| Phase 3: Karabiner stable path | **Not qualified as a usable product backend** | Transactions, conflict handling, configuration application/readback, rollback, backup retention, emergency disable and real supported-version behavior. Existing spikes are not product delivery. |
| Phase 4: VIA/Vial Beta | **Not qualified** | Separate definition/protocol/dialect/importer/device evidence, safe export/readback, and the specified real-keyboard coverage. Synthetic round trips do not establish device compatibility. |
| Full v1 / public distribution | **Not qualified** | PRD §15 requirements, FR-P6 full password backup, Intel/full support matrix, public name/license decision, signing/notarization and backend requirements remain. |

Requirements remain in [PRD](PRD.md) and [architecture §15](TECHNICAL_ARCHITECTURE.md#15-分阶段交付与发布门禁).
Current Phase 1 evidence is in [acceptance](PHASE1_ACCEPTANCE.md), not the old T24
projection or the baseline-bound `milestone-allocation.json`.

## Recommended next work, not yet authorized as an implementation goal

1. Make local development use maintainable: document a reproducible Release build,
   update and signing-renewal path that preserves the trial's identity/data. The
   installed development profile expires 2026-10-07 at 17:39:57 Asia/Shanghai.
   Do not copy trial data into a daily identity or widen the observed platform
   allowance without evidence. macOS 14+ is a deployment floor, not broad support.
2. Integrate the existing Phase 2 statistics and explanatory logical previews into
   the product. Reuse the existing analysis engine and protected snapshots; make
   key/application labels understandable, retain exact/unknown provenance, and
   cover empty, insufficient-sample, hidden and unavailable states.
3. Map FR-R1–R7 and FR-E1–E2 to implemented behavior and remaining work. The current
   engine accepts no complete physical evidence chain and performs no backend
   conflict/applicability verification. A preset supplies geometry, not verified
   firmware mapping. A logical-preview increment must not be called full G2.
4. Use synthetic boundary/regression data for 19/20 uses, one/two days, 14 active
   days, 70% application share, date rollback, privacy invalidation and restart.
   Schedule only the smallest changed-surface owner check after automatic results;
   do not require two days of manual typing or repeat completed Phase 1 rounds.

Phase 3/4 application/export follows its original safety requirements. This
recommendation does not waive physical scoring, manual-trigger confirmation,
backup, compatibility or public-release requirements to declare an easier success.

## Meaning of completion and historical status

- A scoped MVP completion means the approved scope and cited observations, not
  every full-product gate or every historical runner has become PASS.
- Signed Release denotes the build configuration and development-signed candidate;
  it does not mean notarized/publicly distributed release.
- Automated package/unsigned build CI, real Keychain scenarios, user-supplied UI
  observations and performance measurements remain distinct evidence layers.
- Old BLOCKED/FAIL/SKIPPED records remain truthful for their inputs and dates.
  A consumed preparation file is not a request to relaunch. Local `/private/tmp`
  evidence paths may expire; the versioned reports retain their assertions and
  limits, but do not guarantee raw artifacts remain independently reproducible.
- See [the document index](STATUS_INDEX.md) for current guidance versus records.
