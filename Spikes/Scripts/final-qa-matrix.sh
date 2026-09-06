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
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
[[ "$seed" == phase0-final && "$output" == /tmp/* ]] || { printf 'FINAL_QA=FAIL reason=arguments\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-final-qa.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
scratch="$tmp_dir/build"
swift build --package-path Spikes --scratch-path "$scratch" --product EvidenceValidator >/dev/null
bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)/EvidenceValidator"

if [[ -n "$fixture" ]]; then
  [[ -d "$fixture" && ! -L "$fixture" ]] || { printf 'FINAL_QA=FAIL reason=invalid_fixture\n' >&2; exit 1; }
  "$bin" audit-privacy "$fixture" >/dev/null
  printf 'FINAL_QA=PASS fixture=%s\n' "$fixture"
  exit 0
fi

rm -rf "$output"
mkdir -p "$output"
bash Spikes/Scripts/verify-manifests.sh evidence/phase0 >"$output/manifests.txt"
"$bin" evidence/phase0 >"$output/validation.txt"
conclusions="evidence/phase0/conclusions.json"
checks=(
  '.g0.status == "OPEN" and (.g0.blocking_leg_ids | length) == 15'
  '([.o_items[].id] | sort) == (["O1","O2","O3","O4","O5","O6","O7"] | sort)'
  '(.o4_matrix | length) == 15 and all(.o4_matrix[]; has("evidence_path") != has("blocked_ref"))'
  '([.downstream_blocks[].id] | sort) == (["G1","KARABINER_STABLE","VIA_GENERATION","VIAL_BETA","FULL_BACKUP_FINAL_RELEASE"] | sort)'
  '.source_evidence_commit_sha == "d693554bf73363abf8cf6f0f3b888973f48dc357" and .generator_commit_sha == "fa1aa33557a9437fef11804126e9c5ac9dfcd028" and ((.spikes[]|select(.id=="SP-6B")|.dependency_frozen)==false)'
)
mutations=(
  '.g0.status="PASSED"'
  'del(.o_items[] | select(.id=="O6"))'
  '.o4_matrix += [.o4_matrix[0]]'
  'del(.downstream_blocks[0])'
  '(.spikes[]|select(.id=="SP-6B")|.dependency_frozen)=true'
)
: >"$output/matrix.txt"
for index in 0 1 2 3 4; do
  jq -e "${checks[$index]}" "$conclusions" >/dev/null
  forged="$tmp_dir/negative-$index"
  cp -R evidence/phase0 "$forged"
  jq "${mutations[$index]}" "$forged/conclusions.json" >"$tmp_dir/value"
  mv "$tmp_dir/value" "$forged/conclusions.json"
  set +e; "$bin" "$forged" >/dev/null 2>&1; status=$?; set -e
  [[ "$status" -ne 0 ]] || { printf 'FINAL_QA=FAIL reason=negative_case case=C%s\n' "$((index + 1))" >&2; exit 1; }
  printf 'C%s positive=PASS negative=REJECT\n' "$((index + 1))" >>"$output/matrix.txt"
done
jq -S . "$conclusions" >"$output/normalized-a.json"
jq -S . "$conclusions" >"$output/normalized-b.json"
hash_a="$(shasum -a 256 "$output/normalized-a.json" | cut -d ' ' -f 1)"
hash_b="$(shasum -a 256 "$output/normalized-b.json" | cut -d ' ' -f 1)"
[[ "$hash_a" == "$hash_b" ]]
printf 'FINAL_QA=PASS seed=%s cases=5 deterministic_sha256=%s\n' "$seed" "$hash_a"
