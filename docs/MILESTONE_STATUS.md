# Phase 1 milestone: implemented code, independent BLOCKED gates

## Scope and identity

T24 publishes status, not T25 final-candidate freeze. Scoped code implementation
through T20/T22 is complete; **G1 and release remain BLOCKED**. T21/T23 static
checks are present in sibling milestone work / blocked pending host. Their commits
are not prerequisites or merged implementation claims in this report.

Baseline: `064164e47fe2dfb1957ea8fc601269ecb2c8812e`. T24 attempt:
`.omo/evidence/repository-status-next-step/t24-attempt-20260913T225223Z` (called `A`
below). Clean-tree `A/readiness.json` SHA-256:
`24dbbdc8edcad1db97031571804be9a47c8c9ec57916928ce251b4fcf90e1cb1`.
`A/candidate.json` identity:
`21c81a0c0d76ecfd4b6f4946b2acc0f55d8fe8b9c2605375e40100dc57df4910`.
This is an interim binding of that baseline, not a final candidate. Subsequent
commits supersede it as expected by T15. No tracked `evidence/phase1/readiness.json`
is republished, and historical evidence bytes are unchanged.

The [allocation JSON](milestone-allocation.json) enumerates **24 distinct IDs**:
FR-C1–C8, FR-P1–P7, FR-U1–U4, EK1–EK3, FR-R1/R2. FR-P6 appears once, not as a
duplicate waived exception. Each row gives implementation or retained-contract
files, test files, status, independent gates and evidence keys. An
`INDEPENDENT_RETAINED` implementation path identifies the contract/boundary only,
not an implemented backup or recommender. FR-U2's recommendation badge is retained
with the absent recommender; the current interface does not invent recommendations.
`IMPLEMENTED_HOST_BLOCKED` means scoped code exists, not that the entire normative
requirement has passed live qualification. C2/C5/C8 backend retention is fixture
preservation and absent mapping actions, not production backend support.

## Gates: pass, fail, blocked are distinct

| Gate | Code/static outcome | Qualification and next evidence |
|---|---|---|
| G0 / O6 | PASS / RESOLVED from bound historical proof | Not a new host run; `A/readiness.json` historical assessment |
| SP6A | Lifecycle/keyring implementation and fake tests present | BLOCKED: keychainPolicy, sessionLock, restart, sleepWake live receipts |
| G1 capture | T19 composition, bounded capture and generation fencing implemented | BLOCKED: endorsed live capture receipt and SP6A |
| G1 privacy | T20 encrypted canary, serialization inventory, excluded foreground zero-delta and source/binary egress checks pass | BLOCKED: live `t20.network.zeroOutbound` and `t20.persistence.noEventLevelData` receipt; static symbol absence is not measured zero packets |
| G1 encryptedPersistence | Authenticated storage, flush/recovery/reset/key lifecycle code implemented | BLOCKED: endorsed live persistence receipt and SP6A; no plaintext fallback |
| Product performance ARM | T21 sibling work; ARM measurements must retain exact host/build identity | BLOCKED in this baseline publication: no adopted T21 receipt; no extrapolation from unit tests |
| Product performance Intel | T21 sibling static checks only | BLOCKED pending approved Intel macOS 14+ host; independent of backup KDF timing |
| Native UI / accessibility | T22 hostless native matrix, bilingual labels and accessibility checks pass | BLOCKED: system VoiceOver/focus and hosted signed flow qualification remain T23; hostless rendering is not system interaction |
| Signed hosted build | T23 sibling static boundary checks, not a merged or signed-build assertion | BLOCKED pending authorized signing identity/controller and exact hosted build receipt |
| Signing / notarization / public release | Internal codename and build structure only | Independently BLOCKED; signing does not imply notarization or public name/license approval |
| FR-P6 full backup | Retained, not implemented/waived by local encryption | BLOCKED: independent salted/versioned password KDF envelope, Intel timing, dependency freeze and restore proof |
| Karabiner / VIA / Vial | Historical version-axis evidence remains unchanged | Independently BLOCKED: Karabiner version/reload/disable latency; VIA device protocol/dialect/importer; Vial importer/live capture |

There is no newly observed product FAIL promoted to BLOCKED. Q24 failure-lane PASS
means malformed/forged status is rejected; it is not product qualification. A
valid BLOCKED receipt is a known state, while missing allocation, changed evidence
bytes or forged PASS are checker failures. G1 requires **all** applicable local,
privacy, platform and performance receipts; the three projection gates alone do
not cover all normative release requirements.

## User-visible behavior and supported hosts

Screen lock or a crash can lose **all unsaved statistics since the last completed
durable commit**. Previously committed counts remain. The one-second encrypted
flush cadence is a scheduling target only: queued work, delayed timers and slow
fsync mean there is no time or count-loss guarantee. Lock closes capture/reads,
fences late completions and discards volatile deltas; unlock resumes only after
fresh checks and only when collection was expected. No guaranteed Swift/CryptoKit
copy zeroization is promised. See [contract 8](PHASE1_CONTRACT.md#8-durability-and-lock).

Events are not persisted as text or ordered timestamped key sequences. Product-
stamped synthetic events are excluded; suspected unmarked injection is a separate
source-confidence counter, not proof of authentic human input. Bare-key aggregates
have no application bucket. Reliable unattributable shortcuts may use UNKNOWN;
excluded or unreliable foreground closes the gate rather than counting UNKNOWN.
Reset retains exactly `cycleId`, `perChordTotals`, `perBareKeyTotals`,
`distinctActiveDays` plus existing mappings/backups/ignored items/preferences.
No day distribution, `sourceCounts`, `kind` or `scopeClass` survives in CycleSummary.

The deployment floor is **macOS 14+ only**. An ARM development run is not support
for every macOS version. Intel remains pending host evidence; macOS 13 is not
supported. Signed lifecycle qualification remains version/architecture scoped.

## Evidence locations and internal reproduction

Exact receipt hashes and locations are in `milestone-allocation.json.evidence`:
T19 integration happy 11 tests; T20 happy 8 tests and a separate BLOCKED network
host receipt (0 tests); T22 hostless happy 27 tests. Each receipt's adjacent
`stdout`, `stderr` and `exit-status` retain the runner output. These are referenced
in place, not copied as large logs into Git. T21/T23 use the immutable approved
plan identity and remain unqualified here, not fabricated Q21/Q23 PASS receipts.
The baseline inventory supplied for integration is root 350, Spikes 503,
lifecycle 94; it is not relabeled as a new T24 root/lifecycle execution.

Run from the repository root with a fresh owned attempt directory, no credentials:
`A` must be an absolute path for the QA runner.

```sh
bash Spikes/Scripts/verify-current-deliverables.sh --milestone docs/milestone-allocation.json
bash Scripts/phase1-qa.sh task 24 happy --attempt "$A"
bash Scripts/phase1-qa.sh task 24 failure --attempt "$A"
swift test --package-path Spikes --scratch-path "$A/build/spikes"
```

Q24 receipts live at `A/task-24/{happy,failure}/assertion-summary.json`; the final
checker recheck is `A/recheck/task-24/{happy,failure}/assertion-summary.json`
(happy 1 / failure 6, both PASS with zero failures/skips). FULL Spikes output is
`A/full-spikes-clean.log`; preliminary `full-spikes.log` and
`full-spikes-complete.log` are interrupted runs, not completion evidence.
Q24 checks the published reference bytes, actual
receipt outcomes and complete allocation; it does not regenerate old evidence or
authorize host operations. Artifact files must be available to independently
verify their hashes. `MILESTONE_EVIDENCE_ROOT` may point to a portable evidence
bundle containing files named by SHA-256; only byte-identical artifacts are accepted.
Without them verification fails rather than fabricating success.

For a later **clean committed tree**, use a new output path as described in
[PROJECT_STATUS](PROJECT_STATUS.md#authority-and-reproduction), with
`--lifecycle none`. Valid readiness BLOCKED is exit 2, not FAIL. Binding a candidate
can pass integrity while G1 stays BLOCKED. Do not use this report or the baseline
binding as T25 freeze authorization. Final regression, same-build receipt binding,
signing/notarization, public licensing/name, real backend/device matrices and full
backup remain independent next gates.
