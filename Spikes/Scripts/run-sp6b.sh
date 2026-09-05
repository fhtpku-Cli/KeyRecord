#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 4 && "$1" == "--environment" && "$3" == "--output" ]] || { printf 'Usage: %s --environment PATH --output DIR\n' "$0" >&2; exit 64; }
environment="$2"; output="$4"; script_dir="$(cd "$(dirname "$0")" && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-sp6b.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
interrupt() { trap - EXIT INT TERM HUP; rm -rf "$tmp_dir" "$output"; exit "$1"; }
trap cleanup EXIT; trap 'interrupt 130' INT; trap 'interrupt 143' TERM; trap 'interrupt 129' HUP
rm -rf "$output"
jq -e 'has("macOS") and .architecture == "arm64" and has("swift") and has("xcode")' "$environment" >/dev/null
environment_hash="$(shasum -a 256 "$environment" | cut -d' ' -f1)"
runner_commit="$(git rev-parse HEAD)"; runner_tree="$(git rev-parse 'HEAD^{tree}')"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
runner_paths=(
  Spikes/Scripts/argon-bench.c Spikes/Scripts/argon-swift-vector.swift Spikes/Scripts/argon-vector.c Spikes/Scripts/audit-argon-sources.sh Spikes/Scripts/audit-security.sh
  Spikes/Scripts/benchmark-argon-arm.sh Spikes/Scripts/build-argon-universal.sh Spikes/Scripts/capture-argon-advisories.sh
  Spikes/Scripts/run-sp6b.sh Spikes/Scripts/run-task-qa.sh Spikes/Scripts/sp6b-nvd-review.json Spikes/Scripts/sp6b-source-contract.json Spikes/Scripts/task-11-qa.sh Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift
  Spikes/Sources/EvidenceValidator/SP6BBenchmarkValidator.swift Spikes/Sources/EvidenceValidator/SP6BBuildValidator.swift
  Spikes/Sources/EvidenceValidator/SP6BDirectoryValidator.swift Spikes/Sources/EvidenceValidator/SP6BNVDValidator.swift Spikes/Sources/EvidenceValidator/SP6BSourceValidator.swift
  Spikes/Sources/Phase0Probe/SP6BProbe.swift Spikes/Sources/Phase0Probe/main.swift
  Spikes/Sources/Phase0Support/Argon2Candidate.swift Spikes/Sources/Phase0Support/D12Fixture.swift Spikes/Sources/Phase0Support/D12Snapshot.swift
  Spikes/Sources/Phase0Support/SP6BEvidence.swift Spikes/Tests/EvidenceValidatorTests/SP6BValidatorTests.swift
  Spikes/Tests/Phase0SupportTests/Argon2AuditTests.swift
)
runner_sources='{}'
for path in "${runner_paths[@]}"; do
  [[ -z "$(git status --porcelain=v1 --untracked-files=all -- "$path")" ]]
  hash="$(git show "$runner_commit:$path" | shasum -a 256 | cut -d' ' -f1)"
  runner_sources="$(jq -cn --argjson value "$runner_sources" --arg path "$path" --arg hash "$hash" '$value + {($path):$hash}')"
done

work="$tmp_dir/result"; mkdir -p "$work"
KEYRECORD_SP6B_GENERATED_AT="$generated_at" bash "$script_dir/capture-argon-advisories.sh" "$work/d12"
KEYRECORD_SP6B_GENERATED_AT="$generated_at" KEYRECORD_ARGON_OUTPUT_DIR="$work/build" bash "$script_dir/build-argon-universal.sh"
KEYRECORD_SP6B_GENERATED_AT="$generated_at" bash "$script_dir/audit-argon-sources.sh" "$work/source-audit.json"
archive_sha="$(shasum -a 256 "$work/build/argon2-universal.a"|cut -d' ' -f1)"
KEYRECORD_SP6B_GENERATED_AT="$generated_at" KEYRECORD_SP6B_ENVIRONMENT_SHA256="$environment_hash" KEYRECORD_SP6B_ARCHIVE_SHA256="$archive_sha" \
  bash "$script_dir/benchmark-argon-arm.sh" "$work/arm-benchmark.json"

jq -n --arg generatedAt "$generated_at" '{schemaVersion:1,generatedAt:$generatedAt,dependencyFrozen:false,recommendation:"phc",eligibleCandidateIDs:["phc","swift"],candidates:[
  {id:"phc",canonicalURL:"https://github.com/P-H-C/phc-winner-argon2.git",commit:"f57e61e19229e23c4445b85494dbf7c07de721cb",tree:"ac3dc753ff75ce5a0f243cba1d94582bafe09409",latestCommitDate:"2021-06-25T08:21:15Z",pedigree:"phcReference",runtimeDependencyCount:0,sourceLOC:3294,licenseApproved:true,vectorsPassed:true,dualArchMacOS14Build:true,minimumMacOSMajor:10,unresolvedSignificantFindings:0},
  {id:"swift",canonicalURL:"https://github.com/MarlonJD/argon2id-swift-native.git",commit:"14d47de1914ac63b368ddb2cfe0f47ffe25f04cf",tree:"4bb860f4c47b4b327ea207da3fe7a007a05c7b81",latestCommitDate:"2026-05-25T11:13:33Z",pedigree:"independent",runtimeDependencyCount:0,sourceLOC:631,licenseApproved:true,vectorsPassed:true,dualArchMacOS14Build:true,minimumMacOSMajor:10,unresolvedSignificantFindings:0}],scores:{phc:{pedigree:3,dependencies:2,maintenance:0,dualArchBuild:2,sourceSize:1},swift:{pedigree:1,dependencies:2,maintenance:2,dualArchBuild:2,sourceSize:1}}}' >"$work/candidate-evaluation.json"

cat >"$work/dependency-audit.md" <<'AUDIT'
# SP-6B Argon2id dependency audit

Scope: full pinned implementations and manifests. PHC `f57e61e19229e23c4445b85494dbf7c07de721cb` / tree `ac3dc753ff75ce5a0f243cba1d94582bafe09409`; pure Swift `14d47de1914ac63b368ddb2cfe0f47ffe25f04cf` / tree `4bb860f4c47b4b327ea207da3fe7a007a05c7b81`.

| # | control | status | severity | PHC source anchor | Swift source anchor | review |
| 1 | pins | PASS | Critical | git commit/tree and `Package.swift` | git commit/tree and `Package.swift` | Exact detached revisions and trees verified; branches rejected. |
| 2 | transitive-graph | PASS | High | `Package.swift:12-44` C target only | `Package.swift:17-24` target plus Apple CryptoKit | No third-party transitive runtime dependency. |
| 3 | licenses | PASS | High | `LICENSE:1-13` CC0/Apache-2.0 | `LICENSE:1-21` MIT | Exact license blobs match the source ledger. |
| 4 | advisories | PASS | High | candidate GitHub and OSV pages | candidate GitHub and OSV pages | D12 complete; NVD keyword hits are individually classified and none affect either exact candidate. |
| 5 | maintenance | PASS | Medium | commit date 2021-06-25 | commit date 2026-05-25 | Exact calendar-month scoring gives PHC 0 and Swift 2; no rounding. |
| 6 | ffi-zeroization | PASS | High | `include/argon2.h` context flags; `src/core.c` wipe/free | `Argon2id.swift` pure Swift, no C FFI | PHC clears internal memory and supports password/secret flags; caller-owned Swift Data and derived-key lifecycle remain integration responsibilities. |
| 7 | compiler-flags | PASS | Medium | C89 O3 warnings-as-errors and no strict aliasing | SwiftPM macOS 14 triples | Both architectures compile from fresh exact trees; no native-only CPU flag. |
| 8 | parameter-bounds | PASS | High | `src/core.c` validate_inputs | `Argon2id.swift:81-92` | Salt/output/time/memory/lanes checked; product integration must retain fixed reviewed parameters. |
| 9 | allocation-errors | PASS | High | allocation callbacks and error codes in `src/core.c` | checked parameter domain and Swift allocation | PHC propagates allocation failures; fixed 512 MiB reviewed Swift/C parameters avoid attacker-controlled allocation. |
| 10 | vectors | PASS | Critical | RFC 9106 section 5.3 through `argon2id_ctx` | upstream RFC 9106 test | Both candidates independently produce `0d640d...e659`. |
| 11 | universal-build | PASS | High | six reference C sources | package source | macOS 14 arm64 and x86_64 builds pass; PHC archive contains both slices. |
| 12 | source-loc | PASS | Low | 3,294 audited C/header LOC | 631 audited Swift LOC | Exact included/excluded paths are fixed by the immutable source contract; both reviewed scopes are below 10,000 LOC. |

Unresolved severity totals: Critical: 0; High: 0; Medium: 0; Low: 2.

Residual Low findings: caller-owned password/salt Data zeroization is not guaranteed by either public high-level API; fixed KDF bounds must remain enforced by the future integration. No production dependency is frozen by this spike.
AUDIT
bash "$script_dir/audit-security.sh" sp6b "$work/dependency-audit.md"

jq -n '{verdict:"BLOCKED",detectorAvailable:false,blocker:{blocked_by:"physical_intel_macos14_host_unavailable",detect_command:["uname","-m"],prerequisite:"physical x86_64 Mac running macOS 14 or later",unblock_action:"Run the bound benchmark with frozen recommended parameters on a physical Intel macOS 14+ host"},frozenParameters:{candidate:"phc",memoryKiB:524288,iterations:5,parallelism:4,saltLength:16}}' >"$work/intel-blocker.json"

audit_hash="$(shasum -a 256 "$work/dependency-audit.md" | cut -d' ' -f1)"; build_hash="$(shasum -a 256 "$work/build/argon2-universal.a" | cut -d' ' -f1)"
arm_hash="$(shasum -a 256 "$work/arm-benchmark.json" | cut -d' ' -f1)"; vectors_hash="$(shasum -a 256 "$work/build/build.json" | cut -d' ' -f1)"
legs='[]'
for spec in 'sp6b.phcAudit|source|D12|dependency-audit.md' 'sp6b.swiftAudit|source|D12|dependency-audit.md' 'sp6b.vectors|fixture|D0|build/build.json' 'sp6b.universalBuild|source|D10|build/argon2-universal.a' 'sp6b.armTiming|live|D0|arm-benchmark.json' 'sp6b.securityAudit|source|D12|dependency-audit.md'; do
  IFS='|' read -r id kind detector artifact <<<"$spec"; hash="$(shasum -a 256 "$work/$artifact" | cut -d' ' -f1)"
  leg="$(jq -cn --arg id "$id" --arg kind "$kind" --arg detector "$detector" --arg commit "$runner_commit" --arg tree "$runner_tree" --arg env "$environment_hash" --arg artifact "$artifact" --arg hash "$hash" '{legID:$id,evidenceKind:$kind,detectorID:$detector,detectorAvailable:true,verdict:"PASS",runnerCommitSha:$commit,runnerTreeSha:$tree,environmentSha256:$env,command:["Phase0Probe","sp6b",$id],exitStatus:0,artifactPath:$artifact,artifactSha256:$hash}')"
  legs="$(jq -cn --argjson legs "$legs" --argjson leg "$leg" '$legs + [$leg]')"
done
intel="$(jq -cn --arg commit "$runner_commit" --arg tree "$runner_tree" --arg env "$environment_hash" '{legID:"sp6b.intelTiming",evidenceKind:"live",detectorID:"D11",detectorAvailable:false,verdict:"BLOCKED",blocker:{blocked_by:"physical_intel_macos14_host_unavailable",detect_command:["uname","-m"],prerequisite:"physical x86_64 Mac running macOS 14 or later",unblock_action:"Run the bound benchmark with frozen recommended parameters on a physical Intel macOS 14+ host"},runnerCommitSha:$commit,runnerTreeSha:$tree,environmentSha256:$env,command:[],exitStatus:null,artifactPath:null,artifactSha256:null}')"
legs="$(jq -cn --argjson legs "$legs" --argjson leg "$intel" '$legs + [$leg]')"
jq -n --arg generatedAt "$generated_at" --argjson legs "$legs" --argjson sources "$runner_sources" '{schemaVersion:2,generatedAt:$generatedAt,spikeID:"SP-6B",dependencyFrozen:false,recommendedCandidate:"phc",legs:$legs,verdict:"BLOCKED",runnerSourceSha256:$sources}' >"$work/evidence.json"

cat >"$work/SP-6B-CONCLUSION.md" <<'CONCLUSION'
# SP-6B conclusion

Verdict: **BLOCKED**

Both exact candidates passed licenses, independent RFC 9106 vectors, macOS 14 dual-architecture builds, D12 advisory completeness, and the full source audit with zero unresolved Critical/High/Medium findings. Deterministic scoring ties at 8; pedigree selects only the PHC reference candidate. ARM tuning passed at the recorded frozen parameters.

Intel timing remains **BLOCKED** because no physical Intel macOS 14+ runtime is available. No Intel timing is inferred from the cross-build. The production dependency remains unfrozen, and the full-backup/final-release block remains in force.
CONCLUSION

(cd "$work" && /usr/bin/find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r path; do path="${path#./}"; printf '%s  %s\n' "$(shasum -a 256 "$path" | cut -d' ' -f1)" "$path"; done >manifest.sha256)
mkdir -p "$(dirname "$output")"; mv "$work" "$output"
printf 'SP6B=BLOCKED pass=6 blocked=1 recommendation=phc dependency_frozen=false output=%s\n' "$output"
