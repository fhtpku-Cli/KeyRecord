# Phase 1 implementation contract

This document summarizes the ten [fixed implementation contracts](../.omo/plans/repository-status-next-step.md#fixed-implementation-contracts), items 1–10, without replacing them. [Scope](../.omo/plans/repository-status-next-step.md#scope), lines 26–32, supplies owner approval, allocation and precedence. Measured status belongs to [PROJECT_STATUS.md](PROJECT_STATUS.md), not this implementation specification.

## Allocation and owner approval

Implement FR-C1–C8, FR-P1–P5/P7 and supporting native consent/settings/status/aggregate views. FR-C2/C5/C8 tests preserve fixture-seeded backend objects byte-for-byte and expose no mapping actions; do not build a backend merely to test preservation. FR-P6, FR-R/FR-E, backend application/export/rollback and public-release requirements retain independent gates. G1 also requires architecture §12.4 ARM + Intel product-performance evidence, separately from SP6B Intel KDF timing.

The owner-approved lock contract (plan §Scope line 26, 2026-09-12) is: “screen/session lock stops capture and protected-data reads; invalidate volatile key handles and sensitive UI snapshots, resume only after unlock plus fresh key/privacy checks and only if `expectedCollecting` remains true. Do not promise guaranteed zeroization of copies managed by Swift/CryptoKit.”

The approved reset contract retains exactly architecture §5.1 CycleSummary: `cycleId`, `perChordTotals: [(chord, appBucket, total)]`, `perBareKeyTotals: [(keyCode, total)]`, `distinctActiveDays`; plus existing mappings/backups/ignored items/preferences. Daily details are removed. FR-P6 full password backup is independently required, not waived or marked passed here.

Precedence: approved owner contract > PRD normative behavior > architecture normative behavior > verified current evidence for measured facts. Historical receipts/Markdown concern their bound generation only. Contradictions never imply PASS.

## 1. Historical/current separation

Fixed contract 1: preserve `evidence/phase0/**`, old candidate/receipts and ConclusionGenerator v1 semantics byte-identically. Current-readiness modules/commands are additive and reject stale sources while recomputing semantics. Task 15's new `evidence/phase1/readiness.json` will cite exact historical hashes; later SP6A goes under `evidence/phase1/sp6a/`, never over v3 history. Label old dependency lists and stale local prose historical; do not repair them by regenerating evidence.

## 2. Three outcome levels

Fixed contract 2: PASS means the specified assertion actually ran and passed; FAIL means it ran and failed; BLOCKED means missing capability/authorization, unknown detector behavior or incomplete proof. Exits are 0/1/2; malformed or tampered input is FAIL. A successful negative test exits 0 while separately recording the expected tool/product rejection.

## 3. Host prerequisites are not authorization

Fixed contract 3: private, executor-supplied, read-only `A/host.json` binds host ID, architecture/macOS, certificate fingerprint/Team ID, exact test bundle IDs, permitted test Keychain prefix/scratch root, operation allowlist, expiry and approved noninteractive controller executable SHA256. The allowlist covers keychain-create/delete-test-items, screen-lock/unlock, sleep/wake, restart, packet-capture. No passwords/private keys enter the manifest; secrets remain in the existing controller.

Validate actual host/build identity before every effect. Missing/expired/mismatched fields or controller block before mutation. The plan and `/start-work` grant no implicit permission: no TCC/sudoers installation, sudo escalation, credential prompt or production-data access. Fake unit tests need no manifest.

## 4. Signed lifecycle and lock detector

Fixed contract 4: candidate policy is nonsynchronizable data-protection Keychain `WhenUnlockedThisDeviceOnly`; `AfterFirstUnlockThisDeviceOnly` is comparison-only, never fallback. Measure macOS semantics, not assumed iOS guarantees. Independent `SessionLockProvider` plus generation fence enforces product lock even if raw Keychain reads succeed.

Evaluate AppKit session/sleep notifications and the distributed screen lock/unlock pair as version-scoped observed signals. Initialize unknown; require an authoritative controller-provided unlocked witness during qualification, including restart/startup-under-lock and transitions. No inference from focus, elapsed time or successful key reads. Without independently established production-accessible initial state/lock signal, disable that macOS version's capture/read path and mark task 7 BLOCKED. Document selected signals/support envelope; invent/freeze no private API and weaken no behavior.

## 5. Privacy and event contract

Fixed contract 5: gate precedes normalization: `collecting && keyAvailable && sessionUnlocked && secureInputDisabled && reliableForeground && notExcluded`. False/unknown yields zero aggregate and event-derived metadata deltas and clears held-state. Only reliably unattributable foreground becomes UNKNOWN. Product-marked events are dropped; suspected unmarked injection uses a separate source counter and is never claimed authentic.

Events have no timestamp and never become Codable/persisted records. Bare-key types cannot carry appBucket. Local calendar dates may move backward; active-day ordinal advances monotonically on first encounter of a distinct day, not by lexicographic date order.

## 6. Storage wire contract

Fixed contract 6: port measured `AuthenticatedStorageEnvelope` v1: 64-byte authenticated header, UInt32 keyVersion, AES-256-GCM, fresh 12-byte nonce, existing HKDF labels, 8 MiB bound. Do not substitute the architecture's illustrative UInt16 header. Logical identity is length-prefixed UTF-8 `(objectType, schemaVersion, logicalID)`; shard logicalID is length-prefixed `(cycleId, dayKey, aggregateType)`.

Use fixed discovery `manifest.krenc` with expected identity known before decryption. Select the versioned key, validate header locator against recomputed expected identity, then decrypted identity against requested identity: AAD alone cannot prevent complete valid-object swaps. Flat `<64-lowerhex>.krenc` files, random opaque temp names, no probe two-level layout or semantic paths. Root `Application Support/com.keyrecord.app/store` is 0700; regular files 0600, no symlink traversal. Freeze Keychain accessibility only after task 7 passes.

## 7. Bootstrap and recovery ordering

Fixed contract 7: one writer actor. Make data durable before manifest commit; same-locator updates use the single-file rename boundary. Relocation writes new object, commits manifest, then deletes old locator. Retirement scans live entries, fixed manifest, unfinished reset/rotation journals, their old/new/recovery objects and unreconciled owned temp/orphan envelopes. Unknown/unreadable references block retirement; manifest entries alone are insufficient.

Rotation: add key → atomically publish current-version Keychain metadata retaining old keys → migrate data → durably re-encrypt fixed manifest/journals → recover transactions/reconcile owned artifacts → rescan all protected references → atomically mark retirement-pending → exact-delete old key → atomically remove metadata. Reset and retirement serialize through the store actor, never concurrently.

Before metadata publication a new key remains an owned pending candidate, not a replacement for a missing key; after publication retain both for recovery. Resume retirement-pending deletion only after a fresh complete scan. A missing retirement-pending key is tolerated only if that scan proves it unnecessary; other missing keys fail closed. A versioned encrypted journal coordinates reset. Empty storage plus no namespace keys is fresh; a root/manifest lacking a required key is not fresh and must not auto-create replacements. Missing/corrupt manifest is corruption, not permission to delete unindexed data. Clean only proven-owned orphans after authenticated manifest/journal recovery; unknown schema/corrupt envelopes fail closed without deletion.

## 8. Durability and lock

Fixed contract 8: callback performs no disk/Keychain/process/network work; one bounded 4096-event handoff feeds the serial reducer. Overflow closes gate/invalidates generation atomically; no event-derived dropped-count log. Unlocked encrypted flushes target a 1-second scheduling cadence, not a durable latency/count-loss bound. Scheduler delay, queued writes and slow fsync extend the uncommitted interval. Crash/lock can lose all deltas since the last completed durable commit, never previously committed counts.

Pause/quit/reset request flush completion before success; timeout/error explicitly fails and cannot claim data saved. Lock/unknown closes immediately, cancels/fences completions, clears queued events/plaintext snapshots/key references and discards unflushed deltas instead of reading protected data. Already-issued ciphertext-only fsync/rename may finish but cannot publish readable state across the fence. Resume decrypts last durable state after fresh checks. Test delayed timers, queued writes and slow fsync; promise no fixed loss window or guaranteed Swift/CryptoKit copy zeroization.

## 9. Cycle, reset and delete retention

Fixed contract 9: the exact approved summary fields above exclude day distribution, sourceCounts, kind and scopeClass. Commit journal with stable operationID/new cycleID, summary and retained-object hashes before detail deletion. Idempotent order: summary-written → details-removed → new-cycle/preferences-committed → journal-cleared. Recovery converges to one new current cycle and one old summary.

Explicit full-delete stops capture, unregisters login item and removes only app-owned root plus all exact namespace key versions; report each failure and retry idempotently. No applied production backend objects exist in this milestone. Unknown nonempty future backend artifacts block destructive deletion rather than bypass future baseline safeguards. Fixtures still prove opaque backend objects survive reset.

## 10. Native interface

Fixed contract 10: menu bar always exposes state/start/pause/resume/settings/quit. Consent explains local aggregation, excluded contexts, no text/sequence storage, possible loss since last durable commit on crash/lock; rejection means no capture/login registration. Settings cover exclusions, login item, locale, reset and confirmed local deletion. Aggregates expose cycle totals, shortcut/app buckets, bare-key totals, stateful/system/source-confidence and side-unknown labels; no recommendations/mapping controls.

SwiftUI standard macOS controls, system type/semantic colors/SF Symbols; no custom fonts/network assets. EN + zh-Hans, keyboard focus, accessible names, Reduce Motion, high contrast/light/dark. Produce `docs/DESIGN.md` and native primitive/state harness before screens; native screenshots/XCTest, not browser Lighthouse, prove UI.

The surrounding Scope contract fixes Swift 6/macOS 14+, Apple system frameworks, local Core/Capture/Store libraries and a single non-sandboxed hardened-runtime menu-bar process. No helper/daemon/customer CLI, no product link to Phase0Support. Internal bundle ID is `com.keyrecord.app`; authorized local settings supply Team ID, never invented. Release naming/notarization stay later gates. See plan [guardrails](../.omo/plans/repository-status-next-step.md#must-not-have-guardrails-anti-slop-scope-boundaries) and [verification strategy](../.omo/plans/repository-status-next-step.md#verification-strategy).
