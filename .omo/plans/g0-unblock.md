# G0 unlock — locked decisions

Status: accepted 2026-09-09. Branch `feat/g0-unblock-sp1-sp2` from `fb90c0d`.
T1–T6 implemented in `Spikes/`. T7–T10 live capture is **not** authorized on this host.

## Immutable baseline

- `origin/main` = `HEAD` at branch creation = `fb90c0d99a88e87aff16b9f45124278710d080ff`
- Do not amend/squash/rebase/force-push.
- Do not overwrite `.omo/evidence/phase0-final-candidate.json`, `phase0-final-reviews.json`, `final-reviews/`, `final-review-logs/`.
- Do not change Phase 1 production targets (`KeyRecordApp|Core|Capture|Store|Backends`).
- `sp6a.keychainSelection` is **not** part of G0.

## Arming (no prompt, no Karabiner write, no sleep on this machine)

- SP-1 live: `KEYRECORD_SP1_LIVE_EXECUTION=1`
- SP-2 v2 artifact: `KEYRECORD_SP2_LIVE_AGGREGATE_V2=1`
- SP-2 live: `KEYRECORD_SP2_LIVE_EXECUTION=1`
- Without arming: D1 synthetics/models may run; live legs are `live_execution_not_armed` (SP-1 schema v3) or remain historical INCONCLUSIVE (SP-2 v1 default).
- Isolated Karabiner profile name: `KeyRecord-Phase0-SP1`. Mapping: F18→F19 (codes 79/80). Probe never writes Karabiner config.
- Listen-only taps only. `CGEventPost` / `CGEvent.post` banned in `audit-source-boundaries.sh`.

## SP-1

- Schema v3 when D1 is available. v1 (no D1) and v2 (historical D1 + not-implemented blockers) remain valid.
- Tap selection: prefer session if both matrices pass; otherwise annotated; otherwise none.
- PASS = selected matrix + all ancillary with identical `selectedTapIdentity`. The other matrix may PASS/FAIL/INCONCLUSIVE/BLOCKED.
- Controlled shortcuts: Shift-Command-3 and Control-Up; observed or explicit absent; never “unused”.

## SP-2

- Default: unchanged v1 zero live artifact + INCONCLUSIVE/BLOCKED.
- v2 live JSON is counter-only (`SP2LiveAggregateV2`). No keystream/timestamp/bundleID fields.
- Shared artifact may have nonzero totals; per-leg `dataDelta`/`metaDelta` stay 0 except `frontmostKnown` / `frontmostUnattributable` may be 1 on PASS.
- `sleepWake` never PASS unless sleep/wake is confirmed on a D4 host.

## G0 PASSED (conclusions only; spike `g0Status` stays OPEN)

All required SP-1 + SP-2 legs PASS; selected tap identity bound; O6 RESOLVED; `conclusions.json` `g0.status==PASSED` and empty `blocking_leg_ids`; G1 still lists `sp6a.keychainSelection`.
Non-selected SP-1 matrix does not block G0.

## Staging later (T7–T10)

`/tmp/keyrecord-g0-attempt/` then atomic replace of `evidence/phase0/sp1` and `sp2`. New bind path `.omo/evidence/g0-candidate.json`. Never overwrite phase0-final-*.
