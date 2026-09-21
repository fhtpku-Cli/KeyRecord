# Current project status

## 2026-09-22 host follow-up and merged repair

PR #3 was merged into `main` as `3f9f31aa0705b750f9c460fd0a37195b94b19ea9`; its tree matches the reviewed `e83e86193f7eecfff23b941c966988864e9d9207`. The final repair revision passed 479 package tests. Both PR/push CI and the subsequent main CI passed. The 42 App boundary/reduction tests and Debug/universal Release builds were measured at `6860c8024f333a01689252d0c9c7f7c347a9895f`; later pre-merge changes were documentation and a deterministic test-overlap correction, not production changes.

Subsequent owner-approved bounded runs of the existing signed Debug candidate observed:

- Lock/unlock followed by explicit menu **Start** restored the aggregate display. One subsequent TextEdit shortcut increased its combined modifier groups by one.
- A system power log confirmed an actual manual sleep and wake, despite existing sleep-prevention settings. After explicit **Start**, displayed prior counts remained and a subsequent TextEdit shortcut increased its combined groups by one.
- During the requested TextEdit exclusion sequence, target counts were unchanged after the excluded inputs and increased by one after exclusion was disabled. The owner later confirmed TextEdit's exclusion switch was off, the requested final setting.

These are single-host, bounded behavioral observations, not complete lifecycle/privacy qualification. Screenshots do not establish zero capture throughout a locked interval; numeric lifetime summaries do not identify individual inputs or prove every intermediate UI state. Exclusion screenshots do not independently show toggle state. Successful termination summaries report no write failures/timeouts, but one lock-recovery run had unequal issued/durable counts and is not proof that every issued flush completed. Later sleep/exclusion summaries had matching counts. A first incomplete lock trial ended by SIGTERM without a summary and is not a successful persistence test.

The signed candidate came from the modifier-display Debug build, before the later movement of diagnostic-path lookup from `ProductComposition` into `AppDelegate`. It was not rebuilt from merged main for these runs. That known change concerns shutdown diagnostics, not modifier reconstruction; source comparison cannot turn the older binary into a qualification of current main or Release. Local provenance and raw evidence remain under `.omo/repair-20260921/{modifier-display,input-pr,lock-validation,sleep-validation,exclusion-validation}/`.

Repeated first inputs reported an unknown modifier side even when the owner used left Command. The adapter supplies family flags and the queue reconstructs sides from observed transitions. A fresh or recovered queue has no observed released state: its first Command change can mean a press or a release while the opposite side remains held. Unknown is therefore a supported outcome, even if a flagsChanged event arrived. An observed release followed by another press permits side recovery. The existing host evidence does not identify the precise event history, so a lost-event or driver fault is not established, and no side is guessed to make the label look precise.

Remaining work includes current-candidate host verification where needed, time-resolved privacy-boundary evidence, permission changes, fast user switching, signed Release and formal hardware/performance/network qualification. Release capture remains blocked. The historical sections below retain their original scope; the bounded observations above supersede only their corresponding pending host scenarios.

## 2026-09-21 bounded input and restart follow-up

Owner-approved runs of the signed Debug product observed three deliberate TextEdit shortcuts added to the displayed aggregate and retained after a normal quit/restart. Two previously identical-looking rows were separate modifier-state groups (side unknown and left). The display now names left/right/both/unknown modifier states and unknown Fn explicitly, without changing grouping or stored counts. English and Chinese synthetic SwiftUI screens were checked in light/dark appearances at normal and narrow widths.

An explicitly enabled DEBUG-only run summary survives per-session diagnostic resets and records numeric counters, successful model-publication totals and read failures on normal termination. It contains no input text, key codes, application identifiers or event timestamps. Model publication is not proof of screen rendering; the bounded owner screenshots provide that separate observation. A crash or forced kill may produce no summary.

At `b46316bbb7c4c0dcc7573619010ae5eecc6eabcb`, final automated verification passed 476 package and 114 App tests with no failures/skips; both GitHub push and PR CI builds passed. The follow-up changes have their own focused regression, localization, native-rendering and build checks; do not treat the older full-suite count as measurement of a newer revision. Local follow-up evidence is under `.omo/repair-20260921/{diagnostic-followup,modifier-display}/` and is not bundled with releases.

This establishes bounded physical-input, observed application attribution, displayed increments and restart persistence on this host. It does not qualify all foreground transitions, exclusions, lock/sleep recovery, signed Release, Intel performance or full G1/public release. No historical formal receipt or milestone gate is rewritten. The earlier repair narrative below records earlier checkpoints; its then-pending capture/CI observations are superseded only by the scoped results above.

## 2026-09-21 repair status (earlier checkpoint)

The 2026-09-21 local repair is implemented on `codex/phase1-repair-20260921` based on `6687c296dbf44abe34f78055e7f830dfbe30771a`. It fixes unknown lock-state fail-closed behavior, Release diagnostic isolation, application attribution/session recovery, unsaved-data protection, production-layer counters, keyboard accessibility and reproducible App testing. Phase 1 still requires bounded real-host validation; it is not reliable-daily-use, full G1 or public-release acceptance.

Fresh final verification on macOS 27.0 (26A428), Xcode 27.0 / Swift 6.4: SwiftPM 476/476 passed (Core 216, Capture 64, Store 157, Integration 39), App hostless XCTest 104/104 passed, zero failed or skipped. The focused lock/reduction/accessibility group passed three consecutive 26-test runs. SwiftPM Release, unsigned App universal Release (arm64 and x86_64) and native Debug test compilation passed. Independent safety rereview cleared two additional repaired recovery races. Build logs retain existing compiler warnings; these results do not claim a warning-free toolchain. Local raw logs are in `.omo/repair-20260921/`, with the reproducible workflow transcript at `verify-local.log` and final results in `final-*.log`. GitHub CI configuration is added but has not run remotely.

The first user-assisted read-only cycle returned `unknown → locked → unknown` through the CGSession field. A second approved 60.4-second cycle found explicit `unlocked → locked → unlocked` through the root IORegistry `IOConsoleLocked` boolean, with matching foreground-session checks throughout. The DEBUG provider now combines explicit witnesses with current-user foreground-session checks before and after the console read; any locked witness or lock notification blocks, and missing/malformed evidence cannot default to unlocked. A read-only driver of the actual provider returns `unlocked` on this host. This is an experimental development implementation: the two system reads are not atomic, and fast user switching, sleep, product notification transitions and physical capture remain unqualified. See `.omo/repair-20260921/CONSOLE-WITNESS-INVESTIGATION.md` and `console-lock-fix-result.md` for the follow-up results; the earlier 104-test full run predates this follow-up.

The 2026-09-20 review at `6687c296dbf44abe34f78055e7f830dfbe30771a` measured 459/459 SwiftPM tests passing, SwiftPM Release compilation passing, native unsigned Debug App test compilation passing, App XCTest 71 pass / 20 fail / 1 skip, and unsigned App Release compilation failing. The App run did not supply `T23_RELEASE_APP`, so Release-dependent failures included an unmet test prerequisite. These are pre-repair measurements, not the current repair's results. Earlier claims of only 14 App failures, a usable current Release bundle, and completed product capture qualification are superseded.

The current product physical-input → attribution → durable-save → restart closure remains pending. A prior bounded harness observation with Karabiner running shows that physical events reached that harness at that time; it does not rule out every driver interaction or verify the product pipeline. The verified DEBUG diagnostics wiring enables measurement and does not by itself prove this closure.

Use [README](../README.md#build-and-test) and `Scripts/verify-local.sh` for ordinary development verification. CI deliberately omits App XCTest and real-host operations; successful unsigned universal compilation is not signing, Intel runtime, or host qualification. The portable normative requirements are in [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

The sections below retain historical checkpoints and existing qualification rules. Their measurements and old handoff references apply to their stated revisions, not automatically to this repair. No historical receipt, sealed evidence or formal blocker is rewritten or waived. Signed lifecycle/lock/keychain qualification, network and ARM/Intel performance, hosted UI/accessibility and FR-P6 remain independently pending or blocked as documented in [MILESTONE_STATUS.md](MILESTONE_STATUS.md).

## Authority and reproduction

This is the current-status entry point, not a new Phase 0 conclusion or a release approval. The repository-contained [approved contract](PHASE1_CONTRACT.md#allocation-and-owner-approval) establishes precedence: owner contract > PRD normative behavior > architecture normative behavior > verified current evidence for measured facts. Requirement allocation and implementation constraints are in [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

The observation below was rechecked from a clean schema-v1 projection at base `064164e47fe2dfb1957ea8fc601269ecb2c8812e` in T24. Exact attempt identities are in the milestone report. It is not a promise about a later checkout. Generate a fresh, nonexisting output under the current attempt, then validate it using the built `EvidenceValidator`:

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

Owner-approved behavior (2026-09-12), reproduced in the portable contract: “screen/session lock stops capture and protected-data reads; invalidate volatile key handles and sensitive UI snapshots, resume only after unlock plus fresh key/privacy checks and only if `expectedCollecting` remains true. Do not promise guaranteed zeroization of copies managed by Swift/CryptoKit.”

Reset removes daily details and retains exactly architecture §5.1 CycleSummary fields: `cycleId`, `perChordTotals: [(chord, appBucket, total)]`, `perBareKeyTotals: [(keyCode, total)]`, `distinctActiveDays`; plus existing mappings/backups/ignored items/preferences. No day distribution, `sourceCounts`, `kind` or `scopeClass` survives in the summary. This is approval of behavior, not evidence of implementation. See [contracts 8–9](PHASE1_CONTRACT.md#8-durability-and-lock).

## Acceptance scope

The new checker defaults to `--gate G0`: exit 0 means the verified historical prerequisite is satisfied, **not** G1 or release. It always reports `scope`, overall `readiness_exit`, and `release_claim=false`. `--gate all` preserves the full current-readiness outcome; other gate IDs are explicitly selectable. Missing proof is BLOCKED/2; malformed/tampered/waived evidence is FAIL/1. `--candidate <file>` additionally delegates to task 4's `verify-current-candidate <file> --readiness <file>` when available; unavailable/invalid candidate validation never silently passes. No plan checkbox or document phrase grants acceptance.

`CurrentDeliverablesTests/testHappyReviewerReferenceTable` prints parsed claim-to-field pairs for each bounded status note. These synthetic tests prove acceptance behavior, not current host capabilities; use a fresh real projection for the observed state above.

---

## Corrective round 2026-09-18/20

Scope-limited round on capture, privacy, lifecycle, persistence and exclusion wiring.
It changed no evidence schema, published no projection and claims no gate transition:
every BLOCKED gate above stays BLOCKED, and this is not a G1 or release claim.

Baseline `45d2ba8a1` -> `36d9115d7`, eight commits, 40 files, +3515/-185.

### Defect classes fixed

Seven came from a 2026-09-18 review; six more surfaced only during host verification.
Root causes worth remembering, because each was invisible to the tests that existed:

- A provider assigned **after** `init` returned, so the observer block registered inside the
  initializer captured `nil` - screen lock and unlock were never observed at all.
- The permission gate ran **after** provider validation, so the single production call to
  `CGRequestListenEventAccess()` was unreachable in a stable denied state: the user could
  never be asked.
- Production `FlowActions.loadChoices` was left at its default empty closure, so the
  exclusions list was permanently empty while previews and UI doubles looked correct.
- The status title consulted only lifecycle phase and the key gate. Both look healthy at
  boot, so the menu bar showed "Collecting" with zero store handles and zero counts.
- Recovery called a policy-refresh helper that never starts the event source, then asked
  whether a session was live - necessarily false, so every recovery reported `startFailed`.

### Test counts

Baseline measured 379 executed / 364 passed / **15 failed**. Those 15 were **validator
faults, not product defects**: a crash probe that searched for a build layout the current
backend never emits, and a scratch-directory helper that required an ancestor literally
named `build` (the default is `.build`). After the round: **459 executed, 459 passed, zero
failed, zero skipped**.

Correction from the 2026-09-20 raw-log review: the earlier baseline App log contains 61 pass / 19 fail / 1 skip; the corrective round final log contains 67 pass / 23 fail / 1 skip. The prior 14-failure/identical-set claim was incorrect. Counts are test cases, not assertion totals. The newer review measured 71 pass / 20 fail / 1 skip under its stated prerequisites; none of these failures is waived.

### Historical harness observation

Earlier investigation notes speculated that Karabiner's DriverKit layer was swallowing
physical key events. A bounded 45-second host run with **all four Karabiner daemons
running** observed tap keyDown 168 / keyUp 168, queue accepted 336, normalized 336,
aggregate delta 168, zero closed handoffs and zero tapDisabled events.

That observation refutes the narrow hypothesis that all physical events were swallowed before reaching that harness during that run. It does not establish the cause of the product failure or permanently exclude Karabiner interactions. Secure Input remains an unproven candidate, not a diagnosis.

### Historical gap before the 2026-09-21 repair: layered counters

At this checkpoint, `CaptureDiagnostics` reports which layer of the capture chain stopped, but its per-layer
counters are incremented only by the test harness and unit tests - **never by the shipping
app**. Until they are wired, the chain is verified only as far as "a session exists"; whether
events actually reach the aggregate and become durable has not been observed in production.

The diagnosis now states `counters are not instrumented in this build` rather than reporting
an unwritten zero, because reading one as a measurement previously produced the fabricated
claim that no keyboard event had reached the process.
