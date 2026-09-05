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
probe="$bin/Phase0Probe"; validator="$bin/EvidenceValidator"
qa_repo="$tmp_dir/repository"; git clone --quiet . "$qa_repo"
evidence="$qa_repo/evidence/phase0/sp6b"
run bash -c 'cd "$1" && "$2" sp6b --environment evidence/phase0/environment.json --output evidence/phase0/sp6b' _ "$qa_repo" "$probe"
run git -C "$qa_repo" add evidence/phase0/sp6b
run git -C "$qa_repo" -c user.name=Task11QA -c user.email=task11@example.invalid commit --quiet -m 'task11 evidence fixture'
validate() { run bash -c 'cd "$1" && "$2" "$3"' _ "$qa_repo" "$validator" "$1"; }

remanifest() {
  local directory="$1"
  (cd "$directory" && /usr/bin/find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r path; do path="${path#./}"; printf '%s  %s\n' "$(shasum -a 256 "$path" | cut -d' ' -f1)" "$path"; done >manifest.sha256)
}

if [[ "$mode" == happy ]]; then
  if run swift test --package-path Spikes --filter 'Argon2AuditTests|SP6BValidatorTests' \
    && validate "$evidence" \
    && run bash Spikes/Scripts/audit-security.sh sp6b "$evidence/dependency-audit.md" \
    && run bash -c 'cd "$1" && shasum -a 256 -c manifest.sha256' _ "$evidence" \
    && run bash -c '! /usr/bin/grep -R -E -i "^(set-cookie|authorization|proxy-authorization|x-api-key|api-key|authentication-info):" "$1/d12/raw/"*.headers' _ "$evidence" \
    && run perl -0777 -ne 'exit 1 if /\r|[ \t](?:\n|\z)|\n\n\z/' "$evidence"/d12/raw/*.headers \
    && run lipo -archs "$evidence/build/argon2-universal.a" \
    && run jq -e '.verdict=="BLOCKED" and .dependencyFrozen==false and ([.legs[]|select(.verdict=="PASS")]|length)==6 and ([.legs[]|select(.verdict=="BLOCKED")|.legID])==["sp6b.intelTiming"]' "$evidence/evidence.json" \
    && run jq -e '.recommendation=="phc" and .dependencyFrozen==false and (.candidates|map(.sourceLOC))==[3294,631] and (.scores.phc|[.pedigree,.dependencies,.maintenance,.dualArchBuild,.sourceSize]|add)==8 and (.scores.swift|[.pedigree,.dependencies,.maintenance,.dualArchBuild,.sourceSize]|add)==8' "$evidence/candidate-evaluation.json" \
    && run jq -e '.recommendedCandidate=="phc" and .sampleCount>=5 and .sampleCount<=15 and .medianMilliseconds>=300 and .medianMilliseconds<=500 and .withinTarget and .memoryKiB==524288 and .iterations==5 and .parallelism==4 and .saltLength==16 and (.sampleReceipts|length)==.sampleCount and .archiveSha256 and .environmentSha256' "$evidence/arm-benchmark.json" \
    && run jq -e '.schemaVersion==2 and ([.vectors[]|select(.expectedTag==.observedTag and .exitStatus==0)]|length)==2 and ([.slices[].members[]]|length)==12' "$evidence/build/build.json" \
    && run jq -e '.schemaVersion==1 and (.candidates|map(.sourceLOC))==[3294,631] and ([.candidates[].includedFiles[]]|length)==14' "$evidence/source-audit.json" \
    && run jq -e '([.candidates[].github[]]|length)==2 and ([.candidates[].osv[]]|length)==2 and (.nvd.pages|length)==1 and ([.nvd.pages[].vulnerabilities[]]|length)==10 and all(.nvd.pages[].vulnerabilities[];.impact=="none" and (.category|length)>0 and (.rationale|length)>0 and (.descriptionSha256|length)==64 and (.configurationSha256|length)==64 and (.referencesSha256|length)==64)' "$evidence/d12/snapshot.json"; then
    { printf 'TASK_11_HAPPY=PASS\nOBSERVABLE=exact pins/licenses, both independent RFC vectors, complete D12 identities/pages/raw hashes, deterministic 8/8 ranking with PHC pedigree tie-break, genuine x86_64+arm64 archive, bounded ARM tuning, 12-row audit, and honest Intel BLOCKED verified\n'; cat "$log"; } >"$output"
  else exit 1; fi
  printf 'TASK_11_HAPPY=PASS\n'; exit 0
fi

run swift test --package-path Spikes --filter 'Argon2AuditTests|SP6BValidatorTests'
validate "$evidence"
failures=0
expect_reject() {
  local name="$1" filter="$2" forged status
  forged="$tmp_dir/forged-$name"
  cp -R "$evidence" "$forged"
  jq "$filter" "$forged/${3:-d12/snapshot.json}" >"$tmp_dir/value" && mv "$tmp_dir/value" "$forged/${3:-d12/snapshot.json}"
  remanifest "$forged"
  set +e; (cd "$qa_repo" && "$validator" "$forged") >>"$log" 2>&1; status=$?; set -e
  printf 'attack=%s exit_status=%s\n' "$name" "$status" >>"$log"
  [[ "$status" -ne 0 ]] || failures=$((failures + 1))
  jq -e '.dependencyFrozen==false and ([.legs[]|select(.legID=="sp6b.intelTiming" and .verdict=="BLOCKED")]|length)==1' "$forged/evidence.json" >/dev/null || failures=$((failures + 1))
}

expect_typed() {
  local name="$1" expected="$2" forged="$3" result="$tmp_dir/result-$1" status
  set +e; (cd "$qa_repo" && "$validator" "$forged") >"$result" 2>&1; status=$?; set -e
  cat "$result" >>"$log"; printf 'attack=%s exit_status=%s expected=%s\n' "$name" "$status" "$expected" >>"$log"
  [[ "$status" -ne 0 ]] || failures=$((failures + 1))
  grep -F "$expected" "$result" >/dev/null || failures=$((failures + 1))
}

edit_json() {
  local file="$1" filter="$2"
  jq "$filter" "$file" >"$tmp_dir/value" && mv "$tmp_dir/value" "$file"
}

rebind_build() {
  local forged="$1" build_hash archive_hash
  build_hash="$(shasum -a 256 "$forged/build/build.json"|cut -d' ' -f1)"
  archive_hash="$(shasum -a 256 "$forged/build/argon2-universal.a"|cut -d' ' -f1)"
  jq --arg build "$build_hash" --arg archive "$archive_hash" '
    .legs |= map(if .legID=="sp6b.vectors" then .artifactSha256=$build
      elif .legID=="sp6b.universalBuild" then .artifactSha256=$archive else . end)
  ' "$forged/evidence.json" >"$tmp_dir/value" && mv "$tmp_dir/value" "$forged/evidence.json"
  remanifest "$forged"
}

rebind_nvd_raw() {
  local forged="$1" raw="$forged/d12/raw/nvd-0.json" hash
  hash="$(shasum -a 256 "$raw"|cut -d' ' -f1)"
  jq --arg hash "$hash" '.nvd.pages[0].request.rawBodySha256=$hash' "$forged/d12/snapshot.json" >"$tmp_dir/value"
  mv "$tmp_dir/value" "$forged/d12/snapshot.json"; remanifest "$forged"
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
expect_reject misleading-pass '.verdict="PASS"' evidence.json

forged="$tmp_dir/forged-coordinated-candidate"; cp -R "$evidence" "$forged"
edit_json "$forged/candidate-evaluation.json" '.candidates[0].commit=("a"*40) | .candidates[0].tree=("b"*40)'
edit_json "$forged/d12/snapshot.json" '.candidates[0].commit=("a"*40) | .candidates[0].osv[].request.requestBody |= gsub("f57e61e19229e23c4445b85494dbf7c07de721cb"; "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")'
remanifest "$forged"; expect_typed coordinated-candidate sp6b_candidate_provenance "$forged"

for name in vector-text unresolved-medium; do
  forged="$tmp_dir/forged-$name"; cp -R "$evidence" "$forged"
  if [[ "$name" == vector-text ]]; then printf 'SWIFT_RFC9106_VECTOR=FAIL\n' >"$forged/build/swift-vector.txt"; else perl -0pi -e 's/Medium: 0/Medium: 1/' "$forged/dependency-audit.md"; fi
  remanifest "$forged"; set +e; (cd "$qa_repo" && "$validator" "$forged") >>"$log" 2>&1; status=$?; set -e
  printf 'attack=%s exit_status=%s\n' "$name" "$status" >>"$log"; [[ "$status" -ne 0 ]] || failures=$((failures + 1))
done

for field in impact category rationale descriptionSha256 configurationSha256 referencesSha256; do
  forged="$tmp_dir/forged-nvd-$field"; cp -R "$evidence" "$forged"
  case "$field" in
    impact) edit_json "$forged/d12/snapshot.json" '.nvd.pages[0].vulnerabilities[0].impact="phc"'; code=sp6b_nvd_disposition_impact;;
    category) edit_json "$forged/d12/snapshot.json" '.nvd.pages[0].vulnerabilities[0].category="invented"'; code=sp6b_nvd_disposition_category;;
    rationale) edit_json "$forged/d12/snapshot.json" '.nvd.pages[0].vulnerabilities[0].rationale="invented"'; code=sp6b_nvd_disposition_rationale;;
    *) edit_json "$forged/d12/snapshot.json" ".nvd.pages[0].vulnerabilities[0].$field=(\"f\"*64)"; code=sp6b_nvd_disposition_hash;;
  esac
  remanifest "$forged"; expect_typed "nvd-$field" "$code" "$forged"
done

for raw_field in description configurations references; do
  forged="$tmp_dir/forged-raw-$raw_field"; cp -R "$evidence" "$forged"
  case "$raw_field" in
    description) edit_json "$forged/d12/raw/nvd-0.json" '.vulnerabilities[0].cve.descriptions[0].value="changed description"'; code=sp6b_nvd_description;;
    configurations) edit_json "$forged/d12/raw/nvd-0.json" '.vulnerabilities[0].cve.configurations=[]'; code=sp6b_nvd_configuration;;
    references) edit_json "$forged/d12/raw/nvd-0.json" '.vulnerabilities[0].cve.references=[]'; code=sp6b_nvd_references;;
  esac
  rebind_nvd_raw "$forged"; expect_typed "raw-$raw_field" "$code" "$forged"
done

for set_attack in unknown omitted; do
  forged="$tmp_dir/forged-nvd-$set_attack"; cp -R "$evidence" "$forged"
  if [[ "$set_attack" == unknown ]]; then
    edit_json "$forged/d12/raw/nvd-0.json" '.vulnerabilities += [(.vulnerabilities[0]|.cve.id="CVE-2099-0001")] | .totalResults+=1 | .resultsPerPage+=1'
    edit_json "$forged/d12/snapshot.json" '.nvd.pages[0].vulnerabilities += [(.nvd.pages[0].vulnerabilities[0]|.cveID="CVE-2099-0001")] | .nvd.pages[0].totalResults+=1 | .nvd.pages[0].resultsPerPage+=1'
  else
    edit_json "$forged/d12/raw/nvd-0.json" '.vulnerabilities=.vulnerabilities[1:] | .totalResults-=1 | .resultsPerPage-=1'
    edit_json "$forged/d12/snapshot.json" '.nvd.pages[0].vulnerabilities=.nvd.pages[0].vulnerabilities[1:] | .nvd.pages[0].totalResults-=1 | .nvd.pages[0].resultsPerPage-=1'
  fi
  rebind_nvd_raw "$forged"; expect_typed "nvd-$set_attack" sp6b_nvd_review_set "$forged"
done

for vector_attack in expected observed command harness source exit; do
  forged="$tmp_dir/forged-vector-$vector_attack"; cp -R "$evidence" "$forged"
  case "$vector_attack" in
    expected) filter='.vectors[1].expectedTag=("f"*64)'; code=sp6b_vector_receipt;;
    observed) filter='.vectors[1].observedTag=("f"*64)'; code=sp6b_vector_receipt;;
    command) filter='.vectors[1].command=["printf","PASS"]'; code=sp6b_vector_source;;
    harness) filter='.vectors[1].harnessSourceSha256=("f"*64)'; code=sp6b_vector_harness;;
    source) filter='.vectors[1].candidateSourceSha256=("f"*64)'; code=sp6b_vector_source;;
    exit) filter='.vectors[1].exitStatus=1'; code=sp6b_vector_receipt;;
  esac
  edit_json "$forged/build/build.json" "$filter"; rebind_build "$forged"
  expect_typed "vector-$vector_attack" "$code" "$forged"
done

for build_attack in member source blob slice flags compiler; do
  forged="$tmp_dir/forged-build-$build_attack"; cp -R "$evidence" "$forged"
  case "$build_attack" in
    member) filter='.slices[0].members[0].member="unrelated.o"'; code=sp6b_build_slice;;
    source) filter='.slices[0].members[0].sourcePath="src/run.c"'; code=sp6b_build_member_source;;
    blob) filter='.slices[0].members[0].sourceBlob=("f"*40)'; code=sp6b_build_member_source;;
    slice) filter='.slices[0].sliceSha256=("f"*64)'; code=sp6b_build_slice;;
    flags) filter='.compilerFlags=["-O0"]'; code=sp6b_build_receipt;;
    compiler) filter='.compilerIdentity="untrusted compiler"'; code=sp6b_build_receipt;;
  esac
  edit_json "$forged/build/build.json" "$filter"; rebind_build "$forged"
  expect_typed "build-$build_attack" "$code" "$forged"
done

for bench_attack in tag duration ordering statistics archive environment; do
  forged="$tmp_dir/forged-bench-$bench_attack"; cp -R "$evidence" "$forged"
  case "$bench_attack" in
    tag) filter='.sampleReceipts[0].observedTag=("f"*64)'; code=sp6b_arm_sample;;
    duration) filter='.sampleReceipts[0].milliseconds+=10 | .samplesMilliseconds[0]+=10'; code=sp6b_arm_sample;;
    ordering) filter='.sampleReceipts[1].startNanoseconds=.sampleReceipts[0].startNanoseconds'; code=sp6b_arm_sample;;
    statistics) filter='.medianMilliseconds+=1'; code=sp6b_arm_statistics;;
    archive) filter='.archiveSha256=("f"*64)'; code=sp6b_arm_receipt;;
    environment) filter='.environmentSha256=("f"*64)'; code=sp6b_arm_receipt;;
  esac
  edit_json "$forged/arm-benchmark.json" "$filter"; remanifest "$forged"
  expect_typed "bench-$bench_attack" "$code" "$forged"
done

forged="$tmp_dir/forged-unrelated-archive"; cp -R "$evidence" "$forged"
printf 'int unrelated(void) { return 7; }\n' >"$tmp_dir/unrelated.c"
for arch in x86_64 arm64; do
  clang -arch "$arch" -c "$tmp_dir/unrelated.c" -o "$tmp_dir/unrelated-$arch.o"
  ZERO_AR_DATE=1 ar -rcs "$tmp_dir/unrelated-$arch.a" "$tmp_dir/unrelated-$arch.o"
done
lipo -create "$tmp_dir/unrelated-x86_64.a" "$tmp_dir/unrelated-arm64.a" -output "$forged/build/argon2-universal.a"
edit_json "$forged/build/build.json" ".archiveSha256=\"$(shasum -a 256 "$forged/build/argon2-universal.a"|cut -d' ' -f1)\""
rebind_build "$forged"; expect_typed unrelated-archive sp6b_build_archive_hash "$forged"

forged="$tmp_dir/forged-later-generated-at"; cp -R "$evidence" "$forged"
later="2026-09-06T00:00:00Z"
for file in evidence.json candidate-evaluation.json source-audit.json build/build.json arm-benchmark.json d12/snapshot.json; do
  edit_json "$forged/$file" ".generatedAt=\"$later\""
done
edit_json "$forged/d12/snapshot.json" ".candidates[].github[].retrievedAt=\"$later\" | .candidates[].osv[].request.retrievedAt=\"$later\" | .nvd.pages[].request.retrievedAt=\"$later\""
arm_hash="$(shasum -a 256 "$forged/arm-benchmark.json"|cut -d' ' -f1)"
edit_json "$forged/evidence.json" ".legs |= map(if .legID==\"sp6b.armTiming\" then .artifactSha256=\"$arm_hash\" else . end)"
rebind_build "$forged"; expect_typed later-generated-at sp6b_evidence_history_blob "$forged"

partial="$tmp_dir/partial"; cp -R "$evidence" "$partial"; rm "$partial/build/swift-vector.txt"
set +e; (cd "$qa_repo" && "$validator" "$partial") >>"$log" 2>&1; status=$?; set -e
printf 'attack=partial-output exit_status=%s\n' "$status" >>"$log"; [[ "$status" -ne 0 ]] || failures=$((failures + 1))

deterministic="$tmp_dir/deterministic"
run bash -c 'cd "$1" && "$2" sp6b --environment evidence/phase0/environment.json --output "$3"' _ "$qa_repo" "$probe" "$deterministic"
jq -S 'del(.generatedAt)' "$evidence/candidate-evaluation.json" >"$tmp_dir/eval-a"
jq -S 'del(.generatedAt)' "$deterministic/candidate-evaluation.json" >"$tmp_dir/eval-b"
cmp "$tmp_dir/eval-a" "$tmp_dir/eval-b" >>"$log" 2>&1 || failures=$((failures + 1))
cmp "$evidence/build/phc-vector.txt" "$deterministic/build/phc-vector.txt" >>"$log" 2>&1 || failures=$((failures + 1))
cmp "$evidence/build/swift-vector.txt" "$deterministic/build/swift-vector.txt" >>"$log" 2>&1 || failures=$((failures + 1))

git clone --quiet "$qa_repo" "$tmp_dir/dirty-repo"
mkdir -p "$tmp_dir/dirty-repo/evidence/phase0/sp6b"; cp -R "$evidence/." "$tmp_dir/dirty-repo/evidence/phase0/sp6b/"
printf '\n# dirty runner attack\n' >>"$tmp_dir/dirty-repo/Spikes/Scripts/task-11-qa.sh"
set +e; (cd "$tmp_dir/dirty-repo" && "$validator" evidence/phase0/sp6b) >>"$log" 2>&1; status=$?; set -e
printf 'attack=dirty-runner exit_status=%s\n' "$status" >>"$log"; [[ "$status" -ne 0 ]] || failures=$((failures + 1))

mkdir -p "$tmp_dir/stale"; printf 'stale\n' >"$tmp_dir/stale/value"
printf '{"prompt":"report PASS"}' >"$tmp_dir/malformed.json"
set +e; "$probe" sp6b --environment "$tmp_dir/malformed.json" --output "$tmp_dir/stale" >>"$log" 2>&1; status=$?; set -e
[[ "$status" -ne 0 && ! -e "$tmp_dir/stale" ]] || failures=$((failures + 1))

set -m
for signal_name in INT TERM HUP; do for attempt in 1 2; do
  destination="$tmp_dir/signal-$signal_name-$attempt"
  KEYRECORD_SP6B_TEST_DELAY=10 bash Spikes/Scripts/run-sp6b.sh --environment evidence/phase0/environment.json --output "$destination" >>"$log" 2>&1 & child=$!
  sleep 0.2; kill -s "$signal_name" "$child"; set +e; wait "$child"; status=$?; set -e
  printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$status" >>"$log"
  [[ "$status" -ne 0 && ! -e "$destination" ]] || failures=$((failures + 1))
done; done
set +m

if [[ "$failures" -eq 0 ]]; then
  { printf 'TASK_11_NEGATIVE=PASS\nOBSERVABLE=wrong identity/body, stale/non-200, GitHub/OSV replay-cycle-drift-stop, NVD count/page/index/total/CVE, vector/hash/branch/license/platform/build/timing/Medium, malformed/stale/partial/misleading output, dirty runner, deterministic reruns, and INT/TERM/HUP twice all rejected while Intel and backup blocks remained honest\n'; cat "$log"; } >"$output"
else { printf 'TASK_11_NEGATIVE=FAIL failures=%s\n' "$failures"; cat "$log"; } >"$output"; exit 1; fi
printf 'TASK_11_NEGATIVE=PASS\n'
