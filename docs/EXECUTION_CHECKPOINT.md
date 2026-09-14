# Execution checkpoint

Current handoff for the repository-status-next-step milestone. This is documentation only: not approval, not a code change, not a candidate freeze and not a test rerun.

## Status at a glance

- Code checkpoint: HEAD `22cb8e9c7986aa49d92d371ca7afc8ba089338dc`, tree `72d6e9502dbbdebf0bda831a691964a3edf6c4c7`, branch `feat/repository-status-next-step`.
- Content: 11 scoped corrective commits, independently reviewed before they were committed.
- Final verdict: **REJECT**. The final milestone is **BLOCKED**, not complete.
- No current valid frozen candidate and no F1, F2, F3 or F4 approval. No G1 pass and no public-release claim.
- Boulder is paused on external and evidence blockers.

This file was added after the checkpoint. A later documentation commit changes no product bytes and does not rerun or rebind the recorded tests; the receipts below stay bound to `22cb8e9`. Old candidate `ffb79bfd5f49e19ca97787179972381cc6d255cc` and old freeze records remain superseded history.

## Executable verification at the checkpoint

Recorded by the post-commit report against `22cb8e9` on arm64 macOS 26.6.1 with Xcode 26.6 and Swift 6.3.3.

| Suite or build | Recorded result |
|---|---|
| Root SwiftPM tests | 375 passed, 0 failed, 0 skipped |
| Spikes SwiftPM tests | 530 executed, 525 passed, 5 named historical skips, 0 failed |
| KeychainLifecycle tests | 94 passed, 0 failed, 0 skipped |
| Hostless App tests, direct xctest | 64 passed, 0 failed, 0 skipped |
| Root Release warnings-as-errors | PASS |
| Unsigned universal App Release build, arm64 and x86_64 | PASS, never launched |
| Unsigned arm64 App build-for-testing | PASS |

The five Spikes skips are named historical cases: two opt-in export and binding probes, two superseded SP2/SP3 canonical-environment cases, and one checked-in SP1 canonical schema case. None is counted as a pass, and the five do not meet the final zero-skip requirement.

The unsigned universal App build only proves the project compiles for both slices. It is not signed-host proof, not notarization, not a launched hosted app, not native Intel execution, and not system UI or Keychain qualification. App Release warnings-as-errors was not run; only the root Release WAE result is claimed here.

## Corrective areas approved at scoped code level

The combined corrective review returned APPROVE only for these code areas, and REJECT for the overall milestone:

1. Aggregate overflow is a typed error through checked counting, including summary reduction.
2. Production cross-operation nonce history removed; sealing draws a fresh 12-byte nonce with no replacement ring.
3. Bounded flush waiters and writer drains; excess callers allocate no internal tasks and losers cannot resolve twice.
4. Locale persistence at startup and serialized preference saves, including concurrent save races and visible rollback.
5. Unknown future backend artifacts trigger safeguard-required blocking before any key, file, login or consent effect.
6. Four oversized test files split mechanically with discovery identities preserved.
7. Milestone checker is strict physical verification by default; structure-only is explicit and can never return PASS.

Scoped code approval is not F1-F4 approval. Root and hostless tests use fake adapters and unsigned hosts.

## Evidence binding state

The exact-byte reconciliation matched 7 of 8 pinned allocation objects: q19, q20, the historical BLOCKED network receipt, q22, the T24 projection (from the same-attempt `.from-t24` archive), the phase0 history and the PRD. Verified copies live only under `.omo/evidence/repository-status-next-step/evidence-reconciliation-20260914T152149Z/objects/`, named by digest. Sources and declared hashes were not changed.

The eighth object is missing: the original pinned plan bytes with SHA-256 `87842e6a97db39398125307f5f4c864a7c9b4efa04b79ad8e6e91ca382dfcace`. No existing plan, draft or named snapshot matches, and no text, checkbox state or newline was altered to manufacture the digest.

With the relocated objects as the evidence root, the strict physical checker exits 1 with `evidence_unavailable:plan`, and all 15 gates report BLOCKED. Explicit `--structure-only` exits 2 with `physical_evidence=NOT_CHECKED`. That is a known BLOCKED state, not physical verification and not approval.

## Preservation incident

Earlier orchestration improperly removed three pre-existing historical worktrees by forced removal: baseline labels kr-3df401b, kr-raw-16dd and kr-validate-d2a. They were pre-existing workspaces, not disposable task directories.

All three detached committed versions remain reachable through `backup/pre-provenance-squash`. That covers committed content only. Four uncommitted modified working files in kr-raw-16dd, all under `evidence/phase0/`, have no located exact pre-removal backup or patch, and byte recovery is not established. Do not claim the worktrees were preserved, do not claim no data loss, and do not regenerate evidence to stand in for the missing bytes. F4 stays open.

## Nature of local artifacts

Paths under `.omo/evidence/` point to retained local evidence on this machine: receipts, stdout and stderr captures, exit-status files, manifests and the relocated content-addressed objects. They are local records of runs and reviews, not committed portable test fixtures. A clean checkout without those bytes cannot replay physical verification, and the checker fails closed rather than substituting them.

## Remaining inputs

1. Authorized signing identity and team configuration, plus the host manifest and controller for signed hosted builds.
2. A native Intel reference host and full performance windows for ARM and Intel product measurements.
3. Real network attribution and signed UI plus native interaction checks, including live Keychain and session lifecycle receipts.
4. Authentic backups of the pinned plan bytes and the removed worktree working files, or a separately authorized new evidence-generation path that does not relabel the historical snapshot as passed.
5. A zero-skip final suite run bound to one immutable candidate, plan and build, attempted only after the above inputs exist.

## Gates retained independently

FR-P6 full password backup, backend retention, the absent recommendation path, signing and notarization, and public release naming and licensing stay independently retained. No fake or hostless test, unsigned build or historical G0 proof passes, waives or replaces them.

## Source records

- `.omo/notepads/repository-status-next-step/final-remediation.md`
- `.omo/start-work/corrective-checkpoint.json`
- `.omo/evidence/repository-status-next-step/combined-corrections-review-20260914T134019Z/report.md`
- `.omo/evidence/repository-status-next-step/postcommit-corrections-20260914T143428Z/report.md`
- `.omo/evidence/repository-status-next-step/worktree-recoverability-20260914T132912Z/report.md`
- `.omo/evidence/repository-status-next-step/evidence-reconciliation-20260914T152149Z/report.md` and `manifest.json`
