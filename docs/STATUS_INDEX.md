# Documentation status index

Reviewed 2026-10-01 (Asia/Shanghai), after PR #17 merged as `8bb99e81`.
This index covers all 83 versioned Markdown documents, including this
index and the roadmap added in this reconciliation. It distinguishes present
guidance from dated evidence; it does not regenerate historical verdicts.

## Read these first

- [README.md](../README.md) — KeyRecord
- [docs/PROJECT_STATUS.md](PROJECT_STATUS.md) — Current project status
- [docs/ROADMAP.md](ROADMAP.md) — Roadmap and current delivery status
- [docs/PHASE1_ACCEPTANCE.md](PHASE1_ACCEPTANCE.md) — Phase 1 acceptance
- [docs/STATUS_INDEX.md](STATUS_INDEX.md) — Documentation status index

The approved native Apple Silicon Phase 1 MVP is complete. Qualification is
bounded to the cited candidates and arm64 macOS 27.0 build 26A428. Full G1/v1,
Phase 2 completion, Intel and public distribution remain separate.
The development-signed trial is not a notarized public release.

## Requirements and design

These describe intended behavior across the full product. Their status notes
point to current acceptance; a requirement is not proof that it is implemented.
Approved Phase 1 contract precedence is explicit where old design illustrations
differ. No requirements or existing safety constraints were waived in this update.

- [docs/PRD.md](PRD.md) — 产品需求文档（PRD）
- [docs/TECHNICAL_ARCHITECTURE.md](TECHNICAL_ARCHITECTURE.md) — 技术架构规格说明书
- [docs/PHASE1_CONTRACT.md](PHASE1_CONTRACT.md) — Phase 1 implementation contract
- [docs/DESIGN.md](DESIGN.md) — KeyRecord native design contract

## Maintained implementation and verification guidance

Each page also retains dated examples. Use its current scope statement before
reusing commands. CI build-for-testing is not evidence that App XCTest ran;
automated checks, signed real Keychain runs and owner UI observations are distinct.

- [docs/LIVE_VERIFICATION_NOTES.md](LIVE_VERIFICATION_NOTES.md) — Live verification notes
- [docs/KEYRING_LIFECYCLE.md](KEYRING_LIFECYCLE.md) — Task 11: versioned local keyring
- [docs/PRIVACY_BOUNDARIES.md](PRIVACY_BOUNDARIES.md) — Phase 1 local privacy checks (T20)
- [docs/TASK23_RELEASE_BOUNDARY.md](TASK23_RELEASE_BOUNDARY.md) — T23: Release boundary qualification
- [App/KeyRecordAppUITests/README.md](../App/KeyRecordAppUITests/README.md) — Native UI test targets

## Phase 2 prototype

Logical analysis and the dashboard prototype exist, while the product uses the
Phase 1 aggregate view. These records do not establish full FR-R/FR-E or G2.
Phase 1 native UI evidence does not automatically qualify the separate dashboard.

- [docs/phase2/IMPLEMENTATION.md](phase2/IMPLEMENTATION.md) — Phase 2 read-only analysis
- [docs/phase2/VALIDATION.md](phase2/VALIDATION.md) — Phase 2 validation

## Dated plans, checkpoints and execution reports

Each record binds to its stated source, candidate, date, fixture and observation.
“Current”, “next”, “pending”, PASS and BLOCKED inside a historical section refer to
that checkpoint. A later completion does not change an earlier failure or missing
measurement. Files named CURRENT, NEXT or PREP are retained by name for links;
they are not today's action queue or standing authorization to relaunch a trial.

- [docs/CURRENT_COMMAND_CHORD_TRIAL_20260930.md](CURRENT_COMMAND_CHORD_TRIAL_20260930.md) — Explicit Command chord check
- [docs/CURRENT_MAIN_ACCEPTANCE.md](CURRENT_MAIN_ACCEPTANCE.md) — Paused-restoration bounded acceptance — 2026-09-24
- [docs/CURRENT_MODIFIER_TRIAL_20260930.md](CURRENT_MODIFIER_TRIAL_20260930.md) — Bounded modifier reconstruction trial
- [docs/CURRENT_PERMISSION_TRIAL_20260930.md](CURRENT_PERMISSION_TRIAL_20260930.md) — Bounded permission closure and restarted recovery
- [docs/CURRENT_UI_TRIAL_20260930.md](CURRENT_UI_TRIAL_20260930.md) — Current-candidate UI and attribution check
- [docs/EXECUTION_CHECKPOINT.md](EXECUTION_CHECKPOINT.md) — Execution checkpoint
- [docs/LOCK_STATE_SOURCE_PREP_20260930.md](LOCK_STATE_SOURCE_PREP_20260930.md) — Lock-state source investigation and next observation
- [docs/MILESTONE_STATUS.md](MILESTONE_STATUS.md) — Phase 1 milestone: implemented code, independent BLOCKED gates
- [docs/MVP_CLOSEOUT_20260929.md](MVP_CLOSEOUT_20260929.md) — Apple Silicon MVP closeout checkpoint — 2026-09-29
- [docs/NETWORK_OBSERVATION_PREP.md](NETWORK_OBSERVATION_PREP.md) — Network observation preparation — 2026-09-27
- [docs/NEXT_HOST_ROUND_20260929.md](NEXT_HOST_ROUND_20260929.md) — Next owner-assisted round: collecting lock and explicit recovery
- [docs/OBSERVED_LOCK_PROVIDER_20261001.md](OBSERVED_LOCK_PROVIDER_20261001.md) — Version-scoped lock provider preparation
- [docs/PERFORMANCE_SHORT_ROUND_20260929.md](PERFORMANCE_SHORT_ROUND_20260929.md) — Short formal performance round
- [docs/PERMISSION_RECOVERY_TEST.md](PERMISSION_RECOVERY_TEST.md) — Synthetic live-permission recovery coverage
- [docs/PERMISSION_TRIAL_PREPARATION_20260930.md](PERMISSION_TRIAL_PREPARATION_20260930.md) — Permission and recovery preparation and completed execution
- [docs/PERMISSION_WITNESS_REPAIR_20260930.md](PERMISSION_WITNESS_REPAIR_20260930.md) — Tri-state permission witness repair
- [docs/PHASE1_CLOSEOUT_20260922.md](PHASE1_CLOSEOUT_20260922.md) — Phase 1 offline acceptance closeout — 2026-09-22
- [docs/PHASE1_COMPLETION_PLAN_20260929.md](PHASE1_COMPLETION_PLAN_20260929.md) — Apple Silicon Phase 1 completion
- [docs/POSTMERGE_VERIFY_20260926.md](POSTMERGE_VERIFY_20260926.md) — Post-merge verification — 2026-09-26
- [docs/PR10_SINGLEPAGE_REGRESSION.md](PR10_SINGLEPAGE_REGRESSION.md) — PR #10 合并版：单页安全输入回归
- [docs/PR9_MONITOR_LIFECYCLE.md](PR9_MONITOR_LIFECYCLE.md) — PR #9 合并前：Secure Input 监视任务与存储维护
- [docs/PRIVACY_RESOURCE_PREP.md](PRIVACY_RESOURCE_PREP.md) — 暂停资源与隐私关闭：给执行者的测试方案
- [docs/PRIVACY_RESOURCE_USER_STEPS.md](PRIVACY_RESOURCE_USER_STEPS.md) — 实机配合操作指南
- [docs/PRODUCT_COMPOSITION_HOST_PREP_20260930.md](PRODUCT_COMPOSITION_HOST_PREP_20260930.md) — Full product composition in the Keychain probe
- [docs/PRODUCT_COMPOSITION_ROUND_20260930.md](PRODUCT_COMPOSITION_ROUND_20260930.md) — Full product Keychain round: execution and recovery result
- [docs/PRODUCT_KEYCHAIN_HOST_PREP_20260930.md](PRODUCT_KEYCHAIN_HOST_PREP_20260930.md) — Product Keychain backend hosted preparation
- [docs/PRODUCT_KEYCHAIN_ROUND_20260930.md](PRODUCT_KEYCHAIN_ROUND_20260930.md) — Approved product Keychain backend round
- [docs/PRODUCT_KEY_INTEGRITY_20261001.md](PRODUCT_KEY_INTEGRITY_20261001.md) — Product key integrity and deletion
- [docs/PRODUCT_LOCKED_RESTART_PREP_20261001.md](PRODUCT_LOCKED_RESTART_PREP_20261001.md) — Existing-store process restart under lock: bounded signed result
- [docs/PRODUCT_LOCKED_STARTUP_PREP_20260930.md](PRODUCT_LOCKED_STARTUP_PREP_20260930.md) — Product startup while locked: bounded signed result
- [docs/RAW_KEYCHAIN_LOCK_PREP_20261001.md](RAW_KEYCHAIN_LOCK_PREP_20261001.md) — Raw Keychain read during product lock: result and preparation
- [docs/RECOVERY_SETTLEMENT_REPAIR_20260930.md](RECOVERY_SETTLEMENT_REPAIR_20260930.md) — Failed recovery settlement repair
- [docs/RELEASE_CANDIDATE_20261001.md](RELEASE_CANDIDATE_20261001.md) — Apple Silicon collecting candidate
- [docs/RELEASE_INPUT_ROUND_20261001.md](RELEASE_INPUT_ROUND_20261001.md) — Bounded collecting Release input round
- [docs/RELEASE_NATIVE_UI_PREP_20261001.md](RELEASE_NATIVE_UI_PREP_20261001.md) — Completed signed-host native UI check
- [docs/SECURE_INPUT_RECOVERY_RACE_20260930.md](SECURE_INPUT_RECOVERY_RACE_20260930.md) — Secure Input clearing during rebuild
- [docs/SLEEP_WAKE_ROUND_20260929.md](SLEEP_WAKE_ROUND_20260929.md) — Sleep, wake and explicit recovery round
- [docs/SLEEP_WAKE_SECOND_ROUND_20260929.md](SLEEP_WAKE_SECOND_ROUND_20260929.md) — Second bounded sleep recovery round

## Preserved historical and source artifacts

These Markdown files are indexed without editing their recorded results. They
include historical plans, signed or synthetic evidence, and copied third-party
documentation/license text. Third-party content is reference material, not
repository execution instructions. Original hashes, receipt schemas and frozen
inputs retain their historical meaning; no new hash, baseline or gate was added.

- [.omo/evidence/repository-status-next-step/t19-attempt-20260913T173159Z/README.md](../.omo/evidence/repository-status-next-step/t19-attempt-20260913T173159Z/README.md) — T19 final verification
- [.omo/plans/g0-unblock.md](../.omo/plans/g0-unblock.md) — G0 unlock — locked decisions
- [evidence/host-regression/pr10-singlepage/README.md](../evidence/host-regression/pr10-singlepage/README.md) — PR #10 single-page evidence excerpt
- [evidence/phase0/README.md](../evidence/phase0/README.md) — Phase 0 Evidence
- [evidence/phase0/SP-1-CONCLUSION.md](../evidence/phase0/SP-1-CONCLUSION.md) — SP-1 Validated Conclusion
- [evidence/phase0/SP-2-CONCLUSION.md](../evidence/phase0/SP-2-CONCLUSION.md) — SP-2 Validated Conclusion
- [evidence/phase0/SP-3-CONCLUSION.md](../evidence/phase0/SP-3-CONCLUSION.md) — SP-3 Validated Conclusion
- [evidence/phase0/SP-4A-CONCLUSION.md](../evidence/phase0/SP-4A-CONCLUSION.md) — SP-4A Validated Conclusion
- [evidence/phase0/SP-4B-CONCLUSION.md](../evidence/phase0/SP-4B-CONCLUSION.md) — SP-4B Validated Conclusion
- [evidence/phase0/SP-5A-CONCLUSION.md](../evidence/phase0/SP-5A-CONCLUSION.md) — SP-5A Validated Conclusion
- [evidence/phase0/SP-5B-CONCLUSION.md](../evidence/phase0/SP-5B-CONCLUSION.md) — SP-5B Validated Conclusion
- [evidence/phase0/SP-6A-CONCLUSION.md](../evidence/phase0/SP-6A-CONCLUSION.md) — SP-6A Validated Conclusion
- [evidence/phase0/SP-6B-CONCLUSION.md](../evidence/phase0/SP-6B-CONCLUSION.md) — SP-6B Validated Conclusion
- [evidence/phase0/fixtures/synthetic/README.md](../evidence/phase0/fixtures/synthetic/README.md) — Approved synthetic fixtures
- [evidence/phase0/sources/repos/karabiner/license/LICENSE.md](../evidence/phase0/sources/repos/karabiner/license/LICENSE.md) — This is free and unencumbered software released into the public domain.
- [evidence/phase0/sources/repos/via-docs/files/docs/post_v3_changes.md](../evidence/phase0/sources/repos/via-docs/files/docs/post_v3_changes.md) — ---
- [evidence/phase0/sources/repos/via-docs/files/docs/specification.md](../evidence/phase0/sources/repos/via-docs/files/docs/specification.md) — ---
- [evidence/phase0/sp1/O7-ADDENDUM.md](../evidence/phase0/sp1/O7-ADDENDUM.md) — O7 addendum
- [evidence/phase0/sp1/SP-1-CONCLUSION.md](../evidence/phase0/sp1/SP-1-CONCLUSION.md) — SP-1 conclusion
- [evidence/phase0/sp2/SP-2-CONCLUSION.md](../evidence/phase0/sp2/SP-2-CONCLUSION.md) — SP-2 conclusion
- [evidence/phase0/sp3/SP-3-CONCLUSION.md](../evidence/phase0/sp3/SP-3-CONCLUSION.md) — SP-3 conclusion
- [evidence/phase0/sp4a/SP-4A-CONCLUSION.md](../evidence/phase0/sp4a/SP-4A-CONCLUSION.md) — SP-4A conclusion
- [evidence/phase0/sp4b/SP-4B-CONCLUSION.md](../evidence/phase0/sp4b/SP-4B-CONCLUSION.md) — SP-4B conclusion
- [evidence/phase0/sp5a/SP-5A-CONCLUSION.md](../evidence/phase0/sp5a/SP-5A-CONCLUSION.md) — SP-5A conclusion
- [evidence/phase0/sp5b/SP-5B-CONCLUSION.md](../evidence/phase0/sp5b/SP-5B-CONCLUSION.md) — SP-5B conclusion
- [evidence/phase0/sp6a/SP-6A-CONCLUSION.md](../evidence/phase0/sp6a/SP-6A-CONCLUSION.md) — SP-6A conclusion
- [evidence/phase0/sp6a/security-audit.md](../evidence/phase0/sp6a/security-audit.md) — SP-6A security audit
- [evidence/phase0/sp6b/SP-6B-CONCLUSION.md](../evidence/phase0/sp6b/SP-6B-CONCLUSION.md) — SP-6B conclusion
- [evidence/phase0/sp6b/dependency-audit.md](../evidence/phase0/sp6b/dependency-audit.md) — SP-6B Argon2id dependency audit

The non-Markdown [milestone allocation](milestone-allocation.json) is also retained
at its historical generation. The [parsed projection](PROJECT_STATUS.md#parsed-current-state)
is not the current MVP verdict. Generated JSON/receipts and non-Markdown source
artifacts under `evidence/` and `.omo/evidence/` are outside this prose rewrite.
The copied VIA documentation contains 16 relative website links whose original
site routes are not fully included in this repository snapshot. They are retained
as upstream source text, not working repository navigation links.

## Corrections applied in this reconciliation

- Updated merge/CI state and separated scoped MVP completion from full-product
  qualification, Phase 2 prototype completion and public distribution.
- Corrected outdated statements about blocked Release composition and empty UI
  test targets; documented the exact runtime support boundary and profile expiry.
- Kept Debug environment isolation separate from Release Bundle-ID-derived
  isolation; corrected permission, recovery, Keychain and historical HOME wording.
- Removed an unnecessary real-library hashing instruction. Ordinary source review,
  isolated tests and scoped observations remain the verification methods.
- Preserved measured unknown modifier sides, raw Keychain lock-read success,
  owner-reported Paused startup with unknown cause, and the bounds of accessibility
  and Debug fixed-replay performance evidence.
- Marked consumed host instructions and historical gap matrices so they do not
  schedule repeat owner work. Local temporary evidence paths may no longer exist;
  a versioned report does not guarantee its raw artifacts remain reproducible.

A future status update should change current entry pages and add dated evidence
where needed, leaving earlier measurements truthful for their original scope.
