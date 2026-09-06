#!/usr/bin/env bash
set -euo pipefail

seed=""
output=""
fixture=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed) seed="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --fixture) fixture="${2:-}"; shift 2 ;;
    *) printf 'FINAL_QA=FAIL reason=arguments\n' >&2; exit 1 ;;
  esac
done

expected_output=/tmp/keyrecord-phase0-final-qa
[[ -z "$fixture" ]] || expected_output=/tmp/keyrecord-phase0-final-qa-negative
[[ "$seed" == phase0-final && "$output" == "$expected_output" ]] || {
  printf 'FINAL_QA=FAIL reason=arguments\n' >&2
  exit 1
}
marker="$output/.keyrecord-final-qa-owned"
if [[ -L "$output" ]]; then
  printf 'FINAL_QA=FAIL reason=output_symlink\n' >&2
  exit 1
elif [[ -e "$output" ]]; then
  [[ -d "$output" && -f "$marker" && ! -L "$marker" && "$(<"$marker")" == 'keyrecord-final-qa:v1' ]] || {
    printf 'FINAL_QA=FAIL reason=output_not_owned\n' >&2
    exit 1
  }
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-final-qa.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM HUP
scratch="$tmp_dir/build"
swift build --package-path Spikes --scratch-path "$scratch" --product EvidenceValidator >/dev/null
bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)/EvidenceValidator"

if [[ -n "$fixture" ]]; then
  [[ -d "$fixture" && ! -L "$fixture" ]] || { printf 'FINAL_QA=FAIL reason=invalid_fixture\n' >&2; exit 1; }
  set +e
  privacy_result="$("$bin" audit-privacy "$fixture" 2>&1)"
  privacy_status=$?
  set -e
  [[ "$privacy_status" -eq 1 && "$privacy_result" == 'ERROR internal_error forbiddenField("leak.json", "keysequence")' ]] || {
    printf 'FINAL_QA=FAIL reason=privacy_fixture status=%s result=%q\n' "$privacy_status" "$privacy_result" >&2
    exit 1
  }
  printf 'ERROR privacy_forbidden_field leak.json keysequence\n' >&2
  exit 1
fi

checks=(
  '.g0.status == "OPEN" and (.g0.blocking_leg_ids | length) == 15'
  '([.o_items[].id] == ["O1","O2","O3","O4","O5","O6","O7"]) and (.o_items[] | select(.id=="O6") | .status) == "OPEN"'
  '(.o4_matrix | length) == 15 and all(.o4_matrix[]; has("evidence_path") != has("blocked_ref"))'
  '([.downstream_blocks[].id] == ["G1","KARABINER_STABLE","VIA_GENERATION","VIAL_BETA","FULL_BACKUP_FINAL_RELEASE"]) and all(.downstream_blocks[]; (.caused_by|length)>0)'
  '.source_evidence_commit_sha == "d693554bf73363abf8cf6f0f3b888973f48dc357" and .generator_commit_sha == "fa1aa33557a9437fef11804126e9c5ac9dfcd028" and ((.spikes[]|select(.id=="SP-6B")|.dependency_frozen)==false)'
)
mutations=(
  '.g0.status="PASSED"'
  '(.o_items[]|select(.id=="O6")|.status)="CLOSED"'
  '.o4_matrix[0].blocked_ref="forged.blocker"'
  '.downstream_blocks[0].caused_by=[]'
  '(.spikes[]|select(.id=="SP-6B")|.dependency_frozen)=true'
)

remanifest() {
  (cd "$1" && shasum -a 256 README.md environment.json privacy-audit.json run-all.json conclusions.json \
    SP-1-CONCLUSION.md SP-2-CONCLUSION.md SP-3-CONCLUSION.md SP-4A-CONCLUSION.md SP-4B-CONCLUSION.md \
    SP-5A-CONCLUSION.md SP-5B-CONCLUSION.md SP-6A-CONCLUSION.md SP-6B-CONCLUSION.md >manifest.sha256)
}

run_matrix() {
  run="$1"
  run_dir="$tmp_dir/run-$run"
  mkdir "$run_dir"
  bash Spikes/Scripts/verify-manifests.sh evidence/phase0 >"$run_dir/manifests.txt"
  set +e
  canonical_result="$("$bin" evidence/phase0 2>&1)"
  canonical_status=$?
  set -e
  [[ "$canonical_status" -eq 0 && "$canonical_result" == 'VALID evidence legs=57 o4=15 g0=OPEN' ]] || {
    printf 'FINAL_QA=FAIL reason=canonical run=%s status=%s result=%q\n' "$run" "$canonical_status" "$canonical_result" >&2
    exit 1
  }
  printf '%s\n' "$canonical_result" >"$run_dir/validation.txt"

  for index in 0 1 2 3 4; do
    case_id="C$((index + 1))"
    set +e
    jq -e "${checks[$index]}" evidence/phase0/conclusions.json >/dev/null 2>&1
    positive_status=$?
    set -e
    [[ "$positive_status" -eq 0 ]] || { printf 'FINAL_QA=FAIL reason=positive run=%s case=%s\n' "$run" "$case_id" >&2; exit 1; }

    forged="$run_dir/negative-$case_id"
    cp -R evidence/phase0 "$forged"
    jq "${mutations[$index]}" "$forged/conclusions.json" >"$run_dir/value.json"
    mv "$run_dir/value.json" "$forged/conclusions.json"
    remanifest "$forged"
    set +e
    negative_result="$("$bin" "$forged" 2>&1)"
    negative_status=$?
    set -e
    [[ "$negative_status" -eq 1 && "$negative_result" == 'ERROR conclusion_recompute_mismatch' ]] || {
      printf 'FINAL_QA=FAIL reason=negative run=%s case=%s status=%s result=%q\n' \
        "$run" "$case_id" "$negative_status" "$negative_result" >&2
      exit 1
    }
    jq -n --arg id "$case_id" --arg negative "$negative_result" \
      '{id:$id,positive:{status:0,result:"PASS"},negative:{status:1,result:$negative}}' >"$run_dir/$case_id.json"
  done

  jq -s --arg canonical "$canonical_result" \
    '{canonical:{status:0,result:$canonical},cases:.}' "$run_dir"/C?.json >"$run_dir/result.json"
  jq -S . "$run_dir/result.json" >"$run_dir/normalized.json"
}

run_matrix 1
run_matrix 2
hash_1="$(shasum -a 256 "$tmp_dir/run-1/normalized.json" | cut -d ' ' -f 1)"
hash_2="$(shasum -a 256 "$tmp_dir/run-2/normalized.json" | cut -d ' ' -f 1)"
[[ "$hash_1" == "$hash_2" ]] || { printf 'FINAL_QA=FAIL reason=nondeterministic\n' >&2; exit 1; }

if [[ -L "$output" ]]; then
  printf 'FINAL_QA=FAIL reason=output_symlink\n' >&2
  exit 1
elif [[ -e "$output" ]]; then
  [[ -d "$output" && -f "$marker" && ! -L "$marker" && "$(<"$marker")" == 'keyrecord-final-qa:v1' ]] || {
    printf 'FINAL_QA=FAIL reason=output_not_owned\n' >&2
    exit 1
  }
else
  (umask 077; mkdir "$output"; printf 'keyrecord-final-qa:v1\n' >"$marker")
fi

publish_names=(manifests-1.txt manifests-2.txt validation-1.txt validation-2.txt run-1.json run-2.json normalized-1.json normalized-2.json matrix.json matrix.txt)
for name in "${publish_names[@]}"; do
  [[ ! -d "$output/$name" ]] || { printf 'FINAL_QA=FAIL reason=owned_output_entry name=%s\n' "$name" >&2; exit 1; }
  rm -f "$output/$name"
done
cp "$tmp_dir/run-1/manifests.txt" "$output/manifests-1.txt"
cp "$tmp_dir/run-2/manifests.txt" "$output/manifests-2.txt"
cp "$tmp_dir/run-1/validation.txt" "$output/validation-1.txt"
cp "$tmp_dir/run-2/validation.txt" "$output/validation-2.txt"
cp "$tmp_dir/run-1/result.json" "$output/run-1.json"
cp "$tmp_dir/run-2/result.json" "$output/run-2.json"
cp "$tmp_dir/run-1/normalized.json" "$output/normalized-1.json"
cp "$tmp_dir/run-2/normalized.json" "$output/normalized-2.json"
jq -n --arg seed "$seed" --arg hash1 "$hash_1" --arg hash2 "$hash_2" \
  --slurpfile run1 "$tmp_dir/run-1/result.json" --slurpfile run2 "$tmp_dir/run-2/result.json" \
  '{schemaVersion:1,seed:$seed,runHashes:[$hash1,$hash2],runs:[$run1[0],$run2[0]]}' >"$output/matrix.json"
{
  printf 'run=1 sha256=%s\nrun=2 sha256=%s\n' "$hash_1" "$hash_2"
  jq -r '.runs | to_entries[] as $run | $run.value.cases[] | "run=\($run.key + 1) case=\(.id) positive_status=\(.positive.status) positive_result=\(.positive.result) negative_status=\(.negative.status) negative_result=\(.negative.result)"' "$output/matrix.json"
} >"$output/matrix.txt"
printf 'FINAL_QA=PASS seed=%s cases=5 run1_sha256=%s run2_sha256=%s\n' "$seed" "$hash_1" "$hash_2"
