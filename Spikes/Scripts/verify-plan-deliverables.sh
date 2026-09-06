#!/usr/bin/env bash
set -euo pipefail
plan="${1:-}"
evidence="${2:-}"
[[ -f "$plan" && ! -L "$plan" && -d "$evidence" && ! -L "$evidence" ]] || { printf 'PLAN_DELIVERABLES=FAIL reason=invalid_input\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-deliverables.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

if [[ -f "$evidence/conclusions.json" ]]; then
  for task in {1..16}; do
    /usr/bin/grep -Eq "^- \[x\] ${task}\." "$plan" || { printf 'PLAN_DELIVERABLES=FAIL reason=task_unchecked task=%s\n' "$task" >&2; exit 1; }
  done
  bash Spikes/Scripts/verify-manifests.sh "$evidence" >/dev/null
  swift run --package-path Spikes --scratch-path "$tmp_dir/build" EvidenceValidator "$evidence" >/dev/null
  jq -e '
    ([.spikes[].id] | sort) == (["SP-1","SP-2","SP-3","SP-4A","SP-4B","SP-5A","SP-5B","SP-6A","SP-6B"] | sort) and
    ([.o_items[].id] | sort) == (["O1","O2","O3","O4","O5","O6","O7"] | sort) and
    ([.o4_matrix[].id] | length) == 15 and
    all(.o4_matrix[]; has("evidence_path") != has("blocked_ref")) and
    .g0.status == "OPEN" and
    (.o_items[] | select(.id=="O6") | .status) == "OPEN" and
    ((.spikes[] | select(.id=="SP-6B") | .dependency_frozen) == false) and
    ([.downstream_blocks[].id] | sort) == (["G1","KARABINER_STABLE","VIA_GENERATION","VIAL_BETA","FULL_BACKUP_FINAL_RELEASE"] | sort)
  ' "$evidence/conclusions.json" >/dev/null
  bash Spikes/Scripts/audit-doc-writebacks.sh 2ebc4c1b27a9a334755d7e68c92b06215ac24a11 >/dev/null
  [[ -f "$evidence/shared-atomicity/result.json" && -f "$evidence/sp4a/evidence.json" && -f "$evidence/sp4b/evidence.json" ]]
  printf 'PLAN_DELIVERABLES=PASS tasks=16 spikes=9 o_items=7 o4=15\n'
  exit 0
fi

[[ -f "$evidence/evidence.json" ]] || { printf 'PLAN_DELIVERABLES=FAIL reason=missing_conclusions\n' >&2; exit 1; }
jq -e '(.legs | type == "array" and length == 57)' "$evidence/evidence.json" >/dev/null || { printf 'PLAN_DELIVERABLES=FAIL reason=missing_leg\n' >&2; exit 1; }
printf 'PLAN_DELIVERABLES=PASS fixture_legs=57\n'
