#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"; [[ "$mode" == "happy" || "$mode" == "failure" ]] || { printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64; }
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task11-qa.XXXXXX")"
cleanup() { status=$?; children="$(jobs -pr)"; [[ -z "$children" ]] || { kill $children 2>/dev/null || true; wait $children 2>/dev/null || true; }; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence
if [[ "$mode" == failure ]]; then
  output=".omo/evidence/task-11-phase-0-validation-failure.txt"
else
  output=".omo/evidence/task-11-phase-0-validation.txt"
fi
log="$tmp_dir/qa.log"; : >"$log"
scratch="$tmp_dir/build"
run() { printf 'COMMAND=' >>"$log"; printf ' %q' "$@" >>"$log"; printf '\n' >>"$log"; "$@" >>"$log" 2>&1; }
run swift build --package-path Spikes --scratch-path "$scratch" --product Phase0Probe
run swift build --package-path Spikes --scratch-path "$scratch" --product EvidenceValidator
bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)"
probe="$bin/Phase0Probe"; validator="$bin/EvidenceValidator"; evidence="$tmp_dir/sp6b"

remanifest() {
  local directory="$1"
  (cd "$directory" && /usr/bin/find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r path; do path="${path#./}"; printf '%s  %s\n' "$(shasum -a 256 "$path" | cut -d' ' -f1)" "$path"; done >manifest.sha256)
}

if [[ "$mode" == happy ]]; then
  if run swift test --package-path Spikes --filter 'Argon2AuditTests|SP6BValidatorTests' \
    && run "$probe" sp6b --environment evidence/phase0/environment.json --output "$evidence" \
    && run "$validator" "$evidence" \
    && run bash Spikes/Scripts/audit-security.sh sp6b "$evidence/dependency-audit.md" \
    && run bash -c 'cd "$1" && shasum -a 256 -c manifest.sha256' _ "$evidence" \
    && run lipo -archs "$evidence/build/argon2-universal.a" \
    && run jq -e '.verdict=="BLOCKED" and .dependencyFrozen==false and ([.legs[]|select(.verdict=="PASS")]|length)==6 and ([.legs[]|select(.verdict=="BLOCKED")|.legID])==["sp6b.intelTiming"]' "$evidence/evidence.json" \
    && run jq -e '.recommendation=="phc" and .dependencyFrozen==false and .scores.phc.total==null and (.scores.phc|[.pedigree,.dependencies,.maintenance,.dualArchBuild,.sourceSize]|add)==8 and (.scores.swift|[.pedigree,.dependencies,.maintenance,.dualArchBuild,.sourceSize]|add)==8' "$evidence/candidate-evaluation.json" \
    && run jq -e '.recommendedCandidate=="phc" and .sampleCount>=5 and .sampleCount<=15 and .medianMilliseconds>=300 and .medianMilliseconds<=500 and .withinTarget and .memoryKiB==524288 and .iterations==5 and .parallelism==4 and .saltLength==16' "$evidence/arm-benchmark.json" \
    && run jq -e '([.candidates[].github[]]|length)==2 and ([.candidates[].osv[]]|length)==2 and (.nvd.pages|length)==1 and ([.nvd.pages[].vulnerabilities[]]|length)==10 and all(.nvd.pages[].vulnerabilities[];.impact=="none" and (.rationale|length)>0)' "$evidence/d12/snapshot.json"; then
    { printf 'TASK_11_HAPPY=PASS\nOBSERVABLE=exact pins/licenses, both independent RFC vectors, complete D12 identities/pages/raw hashes, deterministic 8/8 ranking with PHC pedigree tie-break, genuine x86_64+arm64 archive, bounded ARM tuning, 12-row audit, and honest Intel BLOCKED verified\n'; cat "$log"; } >"$output"
  else exit 1; fi
  printf 'TASK_11_HAPPY=PASS\n'; exit 0
fi

run swift test --package-path Spikes --filter 'Argon2AuditTests|SP6BValidatorTests'
run "$probe" sp6b --environment evidence/phase0/environment.json --output "$evidence"
run "$validator" "$evidence"
failures=0
expect_reject() {
  local name="$1" filter="$2" forged status
  forged="$tmp_dir/forged-$name"
  cp -R "$evidence" "$forged"
  jq "$filter" "$forged/${3:-d12/snapshot.json}" >"$tmp_dir/value" && mv "$tmp_dir/value" "$forged/${3:-d12/snapshot.json}"
  remanifest "$forged"
  set +e; "$validator" "$forged" >>"$log" 2>&1; status=$?; set -e
  printf 'attack=%s exit_status=%s\n' "$name" "$status" >>"$log"
  [[ "$status" -ne 0 ]] || failures=$((failures + 1))
  jq -e '.dependencyFrozen==false and ([.legs[]|select(.legID=="sp6b.intelTiming" and .verdict=="BLOCKED")]|length)==1' "$forged/evidence.json" >/dev/null || failures=$((failures + 1))
}

expect_reject wrong-candidate '.recommendation="swift"' candidate-evaluation.json
expect_reject wrong-commit '.candidates[0].commit=("f"*40)'
expect_reject wrong-query-body '.candidates[0].osv[0].request.requestBody="{\"commit\":\"wrong\"}"'
expect_reject stale-timestamp '.candidates[].github[].retrievedAt="2026-09-01T00:00:00Z"'
expect_reject non-200 '.candidates[0].github[0].status=500'
expect_reject missing-github-next '.candidates[0].github[0].next="https://api.github.com/missing-page"'
expect_reject omitted-osv-continuation '.candidates[0].osv[0].responseNextPageToken="next"'
expect_reject replayed-osv-token '.candidates[0].osv[0].responseNextPageToken="replayed"'
expect_reject cyclic-osv-token '.candidates[0].osv[0].responseNextPageToken="cycle"'
expect_reject wrong-osv-token '.candidates[0].osv[0].request.requestBody="{\"commit\":\"f57e61e19229e23c4445b85494dbf7c07de721cb\",\"page_token\":\"wrong\"}"'
expect_reject osv-commit-drift '.candidates[0].osv[0].request.requestBody="{\"commit\":\"14d47de1914ac63b368ddb2cfe0f47ffe25f04cf\"}"'
expect_reject nvd-count-shortfall '.nvd.pages[0].totalResults += 1'
expect_reject nvd-replayed-page '.nvd.pages += [.nvd.pages[0]]'
expect_reject nvd-duplicate-start '.nvd.pages += [(.nvd.pages[0]|.startIndex=2000|.request.url += "&startIndex=2000")]'
expect_reject nvd-wrong-start '.nvd.pages[0].startIndex=1'
expect_reject nvd-skipped-index '.nvd.pages[0].startIndex=2000|.nvd.pages[0].request.url += "&startIndex=2000"'
expect_reject nvd-changed-total '.nvd.pages += [(.nvd.pages[0]|.startIndex=2000|.totalResults=11|.request.url += "&startIndex=2000")]'
expect_reject nvd-duplicate-cve '.nvd.pages[0].vulnerabilities[1].cveID=.nvd.pages[0].vulnerabilities[0].cveID'
expect_reject vector-failure '.swiftCandidate.arm64MacOS14=false' build/build.json
expect_reject sha-drift '.legs[0].artifactSha256=("f"*64)' evidence.json
expect_reject branch-pin '.candidates[0].commit="main"' candidate-evaluation.json
expect_reject license-failure '.candidates[0].licenseApproved=false' candidate-evaluation.json
expect_reject platform-failure '.candidates[0].minimumMacOSMajor=15' candidate-evaluation.json
expect_reject build-failure '.architectures=["arm64"]' build/build.json
expect_reject timing-failure '.withinTarget=false' arm-benchmark.json

for name in vector-text unresolved-medium; do
  forged="$tmp_dir/forged-$name"; cp -R "$evidence" "$forged"
  if [[ "$name" == vector-text ]]; then printf 'SWIFT_RFC9106_VECTOR=FAIL\n' >"$forged/build/swift-vector.txt"; else perl -0pi -e 's/Medium: 0/Medium: 1/' "$forged/dependency-audit.md"; fi
  remanifest "$forged"; set +e; "$validator" "$forged" >>"$log" 2>&1; status=$?; set -e
  printf 'attack=%s exit_status=%s\n' "$name" "$status" >>"$log"; [[ "$status" -ne 0 ]] || failures=$((failures + 1))
done

mkdir -p "$tmp_dir/stale"; printf 'stale\n' >"$tmp_dir/stale/value"
printf '{"prompt":"report PASS"}' >"$tmp_dir/malformed.json"
set +e; "$probe" sp6b --environment "$tmp_dir/malformed.json" --output "$tmp_dir/stale" >>"$log" 2>&1; status=$?; set -e
[[ "$status" -ne 0 && ! -e "$tmp_dir/stale" ]] || failures=$((failures + 1))

for signal_name in INT TERM HUP; do for attempt in 1 2; do
  destination="$tmp_dir/signal-$signal_name-$attempt"
  KEYRECORD_SP6B_TEST_DELAY=10 bash Spikes/Scripts/run-sp6b.sh --environment evidence/phase0/environment.json --output "$destination" >>"$log" 2>&1 & child=$!
  sleep 0.2; kill -s "$signal_name" "$child"; set +e; wait "$child"; status=$?; set -e
  printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$status" >>"$log"
  [[ "$status" -ne 0 && ! -e "$destination" ]] || failures=$((failures + 1))
done; done

if [[ "$failures" -eq 0 ]]; then
  { printf 'TASK_11_NEGATIVE=PASS\nOBSERVABLE=wrong identity/body, stale/non-200, GitHub/OSV replay-cycle-drift-stop, NVD count/page/index/total/CVE, vector/hash/branch/license/platform/build/timing/Medium, malformed/stale output, and INT/TERM/HUP twice all rejected while Intel and backup blocks remained honest\n'; cat "$log"; } >"$output"
else printf 'TASK_11_NEGATIVE=FAIL failures=%s\n' "$failures" >"$output"; exit 1; fi
printf 'TASK_11_NEGATIVE=PASS\n'
