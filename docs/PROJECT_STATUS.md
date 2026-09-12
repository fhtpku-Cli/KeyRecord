# Current project status

## Authority and reproduction

This is the current-status entry point, not a new Phase 0 conclusion or a release approval. The [approved plan](../.omo/plans/repository-status-next-step.md#scope) establishes precedence: owner contract > PRD normative behavior > architecture normative behavior > verified current evidence for measured facts. Requirement allocation and implementation constraints are in [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

The observation below was parsed on 2026-09-12 from a locally generated schema-v1 projection at base `985d6af`. It is not a promise about a later checkout. Generate a fresh, nonexisting output under the current attempt, then validate it using the built `EvidenceValidator`:

```sh
"$VALIDATOR" current-readiness --historical evidence/phase0 --lifecycle none --output "$A/current-projection.json"
"$VALIDATOR" verify-current-readiness "$A/current-projection.json"
bash Spikes/Scripts/verify-current-deliverables.sh "$A/current-projection.json" --validator "$VALIDATOR" --gate all
```

Generation/verification returning 2 means a valid BLOCKED projection, not a parsing failure. The [schema](../Spikes/Sources/EvidenceValidator/CurrentReadinessModels.swift) defines `historicalAssessment`, `bindings`, `gates`, `localLifecycleAssessment` and `retainedReleaseBlockers`; [validation](../Spikes/Sources/EvidenceValidator/CurrentReadinessValidator.swift) checks bound Git identities, exact bytes, strict decoding and semantic recomputation. `status` is computed, not a writable JSON status field. Neither a document title nor a prose keyword is proof. Publishing `evidence/phase1/readiness.json` belongs to task 15; this task does not publish it.

## Parsed current state

Selectors below refer to the validated current projection, with array rows selected by exact `id` (not position or phrase matching).

| Claim / reference ID | Parsed field | Observed value and limit |
|---|---|---|
| current-g0 | `gates[id=G0].status`, `.unresolvedCauses` | PASS, `[]`; verified bound historical proof, not a new live run |
| current-history | `historicalAssessment.g0.status`, `.candidate_selection` | PASSED, session; attribution remains the historical source/generator identities |
| current-o6 | `historicalAssessment.o_items[id=O6].status`, `.evidence_paths`, `.blocker_refs` | RESOLVED, `[sp2/evidence.json]`, `[]`; only the bound SP2 generation, not arbitrary macOS versions |
| current-lifecycle | `localLifecycleAssessment`; `gates[id=SP6A_LOCAL_LIFECYCLE].status`, `.unresolvedCauses` | BLOCKED: `receipt.keychainPolicy`, `receipt.sessionLock`, `receipt.restart`, `receipt.sleepWake` |
| current-implementation | `gates[id=G1_IMPLEMENTATION].status`, `.unresolvedCauses` | BLOCKED: `SP6A_LOCAL_LIFECYCLE`, `receipt.capture`, `receipt.privacy`, `receipt.encryptedPersistence`; G0 is no longer a current cause |
| current-release | `retainedReleaseBlockers[].id`, `.caused_by` | KARABINER_STABLE: `sp3.versionSample`, `sp3.reload`, `sp3.disableLatency`; VIA_GENERATION: `sp4b.deviceProtocol`, `sp4b.keycodeDialect`, `sp4b.importer`; VIAL_BETA: `sp5a.importer`, `sp5b.liveCapture`; FULL_BACKUP_FINAL_RELEASE: `sp6b.intelTiming`, `SP-6B dependency_frozen=false` |
| current-binding | `bindings.commitSha`, `.treeSha`, `.files[].path`, `.files[].sha256`, `.missingPaths` | Recomputed for each checkout; a missing proof blocks and a stale or forged binding fails. Never reuse a projection after changing its bound inputs or HEAD. |

FR-P6 full password backup remains independently required: neither local-storage qualification nor G0/implementation tests waive or pass it. The current schema's G1_IMPLEMENTATION receipt gate is not the entire normative G1 exit: architecture §12.4 ARM + Intel product-performance evidence is additionally required, independent of SP6B Intel KDF timing. Pure tests do not establish signed lifecycle, network or performance evidence. CLI receipt producer approval is empty until an authorized producer is integrated; self-authored receipt claims cannot earn PASS.

## Historical descriptions, not current authority

Line references in this section are pinned to `985d6af`, so bounded insertions in working documentation do not obscure the original locations. Sealed `evidence/phase0/**`, old candidate/receipts and ConclusionGenerator v1 remain byte-identical; no measured history is regenerated to repair wording.

- **SP1 selected-NONE is historical/stale prose:** `evidence/phase0/sp1/SP-1-CONCLUSION.md:5–7` says selected NONE / G0 OPEN even though parsed bound `historicalAssessment.g0` selects session and is PASSED. Preserve the file; do not use its words as a current gate.
- **SP2 no-sleep is historical/stale prose:** `Spikes/Sources/Phase0Probe/SP2Probe.swift:156–158` emits the no-sleep description at line 157; the stored `evidence/phase0/sp2/SP-2-CONCLUSION.md:9` carries that description. Read bound SP2 leg verdicts and O6 disposition instead; this note authorizes no sleep or host operation.
- The **old static dependency list** at `docs/TECHNICAL_ARCHITECTURE.md:889–891,957` and `historicalAssessment.downstream_blocks[id=G1].caused_by` describe the historical dependency model, not the recomputed current causes. G0 must not remain permanently OPEN in current acceptance.
- Stale local status prose at architecture `213,237,274,379,388,938,967` and PRD `673` is labeled beside its location. It cannot override parsed current fields or expand the measured support envelope. ADR-010's pending-review wording at architecture `974` predates the owner approval below.
- `Spikes/Scripts/verify-plan-deliverables.sh:11–27` is the **historical baseline**, unchanged; its OPEN checks and old plan-checkbox checks are not current acceptance.

## Owner-approved lock and reset contract

Approved plan §Scope, line 26 (2026-09-12): “screen/session lock stops capture and protected-data reads; invalidate volatile key handles and sensitive UI snapshots, resume only after unlock plus fresh key/privacy checks and only if `expectedCollecting` remains true. Do not promise guaranteed zeroization of copies managed by Swift/CryptoKit.”

Reset removes daily details and retains exactly architecture §5.1 CycleSummary fields: `cycleId`, `perChordTotals: [(chord, appBucket, total)]`, `perBareKeyTotals: [(keyCode, total)]`, `distinctActiveDays`; plus existing mappings/backups/ignored items/preferences. No day distribution, `sourceCounts`, `kind` or `scopeClass` survives in the summary. This is approval of behavior, not evidence of implementation. See [contracts 8–9](PHASE1_CONTRACT.md#8-durability-and-lock).

## Acceptance scope

The new checker defaults to `--gate G0`: exit 0 means the verified historical prerequisite is satisfied, **not** G1 or release. It always reports `scope`, overall `readiness_exit`, and `release_claim=false`. `--gate all` preserves the full current-readiness outcome; other gate IDs are explicitly selectable. Missing proof is BLOCKED/2; malformed/tampered/waived evidence is FAIL/1. `--candidate <file>` additionally delegates to task 4's `verify-current-candidate <file> --readiness <file>` when available; unavailable/invalid candidate validation never silently passes. No plan checkbox or document phrase grants acceptance.

`CurrentDeliverablesTests/testHappyReviewerReferenceTable` prints parsed claim-to-field pairs for each bounded status note. These synthetic tests prove acceptance behavior, not current host capabilities; use a fresh real projection for the observed state above.
