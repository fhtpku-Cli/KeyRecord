#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'CURRENT_DELIVERABLES=FAIL reason=%s\n' "$1" >&2; exit 1; }
readiness="${1:-}"
[[ $# -gt 0 ]] || fail usage
shift
validator=''
gate=G0
candidate=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || fail usage
  case "$1" in
    --validator) validator="$2" ;;
    --gate) gate="$2" ;;
    --candidate) candidate="$2" ;;
    *) fail unknown_option ;;
  esac
  shift 2
done
case "$gate" in G0|SP6A_LOCAL_LIFECYCLE|G1_IMPLEMENTATION|all) ;; *) fail unknown_gate ;; esac
[[ -f "$readiness" && ! -L "$readiness" ]] || fail invalid_readiness
[[ -n "$validator" && -x "$validator" && ! -d "$validator" ]] || fail validator_required
command -v jq >/dev/null || fail jq_required

# The CLI owns strict decoding, source hashes, receipt trust and semantic recomputation.
overall=0
"$validator" verify-current-readiness "$readiness" || overall=$?
case "$overall" in 0|2) ;; *) fail readiness_validation ;; esac
if [[ -n "$candidate" ]]; then
  [[ -f "$candidate" && ! -L "$candidate" ]] || fail invalid_candidate
  bound=0
  "$validator" verify-current-candidate "$candidate" --readiness "$readiness" || bound=$?
  case "$bound" in
    0) ;;
    2) printf 'CURRENT_DELIVERABLES=BLOCKED scope=candidate\n'; exit 2 ;;
    *) fail candidate_validation ;;
  esac
fi

# A scoped acceptance PASS is never an overall readiness or release PASS.
if [[ "$gate" == all ]]; then
  result="$overall"
else
  status="$(jq -er --arg gate "$gate" '.gates[] | select(.id == $gate) | .status' "$readiness")" || fail missing_gate
  case "$status" in PASS) result=0 ;; FAIL) result=1 ;; BLOCKED) result=2 ;; *) fail invalid_status ;; esac
fi
case "$result" in 0) status=PASS ;; 1) status=FAIL ;; 2) status=BLOCKED ;; esac
printf 'CURRENT_DELIVERABLES=%s scope=%s readiness_exit=%s release_claim=false\n' "$status" "$gate" "$overall"
exit "$result"
