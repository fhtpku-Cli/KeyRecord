#!/usr/bin/env bash
# Task 15 closeout orchestration for the current phase1 baseline assessment.
#
# Pipeline (all artifacts except the controlled publication stay in the attempt
# directory and are never committed):
#   1. project the current readiness from parsed, byte-bound evidence
#      (BLOCKED/2 is a successful projection with unresolved gates, not a failure)
#   2. derive the status table from that strictly decoded projection
#   3. stop before any candidate when the historical G0 proof is not verified
#   4. bind the task 4 interim candidate snapshot (clean committed tree only)
#   5. label the interim envelope (superseded by later commits; task 25 freezes)
#
# This script never reuses an old phase0-final receipt: readiness output is
# exclusively created and every artifact is content-hash cross-checked by the
# EvidenceValidator CLI.
set -euo pipefail

usage() {
  printf 'usage: %s --validator PATH --historical PATH [--lifecycle none] --plan PATH --readiness PATH --status-table PATH --candidate PATH --interim PATH --generated-at ISO8601\n' "$0" >&2
  exit 64
}

validator=''
historical=''
lifecycle='none'
plan=''
readiness=''
status_table=''
candidate=''
interim=''
generated_at=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --validator) validator="$2" ;;
    --historical) historical="$2" ;;
    --lifecycle) lifecycle="$2" ;;
    --plan) plan="$2" ;;
    --readiness) readiness="$2" ;;
    --status-table) status_table="$2" ;;
    --candidate) candidate="$2" ;;
    --interim) interim="$2" ;;
    --generated-at) generated_at="$2" ;;
    *) usage ;;
  esac
  shift 2
done

[[ -n "$validator" && -x "$validator" ]] || { printf 'closeout validator required: %s\n' "${validator:-<missing>}" >&2; exit 1; }
[[ -n "$historical" && -n "$plan" && -n "$readiness" && -n "$status_table" && -n "$candidate" && -n "$interim" && -n "$generated_at" ]] || usage
for output in "$readiness" "$status_table" "$candidate" "$interim"; do
  mkdir -p "$(dirname "$output")"
done

# 1. Current projection. Only 0 and 2 are produced documents; 1 is rejected input.
set +e
generate_out="$("$validator" current-readiness \
  --historical "$historical" --lifecycle "$lifecycle" --output "$readiness" 2>&1)"
generate_rc=$?
set -e
printf '%s\n' "$generate_out"
case "$generate_rc" in
  0 | 2) ;;
  *) exit 1 ;;
esac

# 2. Status table derived from the decoded projection (sealed history stays separate).
table_out="$("$validator" current-status-table --readiness "$readiness" --output "$status_table")"
printf '%s\n' "$table_out"
g0_status="$(printf '%s' "$table_out" | sed -n 's/^CURRENT_STATUS_TABLE=.* g0=\([A-Z]*\).*$/\1/p')"
[[ -n "$g0_status" ]] || { printf 'closeout could not read G0 gate from status table\n' >&2; exit 1; }

# 3. An unverified historical G0 proof blocks before a candidate is ever bound.
if [[ "$g0_status" != "PASS" ]]; then
  printf 'CURRENT_CLOSEOUT=BLOCKED gate=G0 observed=%s stop_before_candidate release_claim=false\n' "$g0_status" >&2
  exit 2
fi

# 4. Task 4 binder: clean committed tree, bound bytes and current state only.
set +e
bind_out="$("$validator" bind-current --plan "$plan" --readiness "$readiness" --output "$candidate" 2>&1)"
bind_rc=$?
set -e
printf '%s\n' "$bind_out"
[[ "$bind_rc" -eq 0 ]] || exit 1

# 5. Interim label; the envelope cross-checks candidate/readiness/table hashes.
"$validator" current-interim-envelope \
  --candidate "$candidate" --readiness "$readiness" --status-table "$status_table" \
  --output "$interim" --generated-at "$generated_at"

printf 'CURRENT_CLOSEOUT=%s interim=true superseded_after_later_commits=true final_freeze=false final_freeze_task=25\n' \
  "$([[ "$generate_rc" -eq 0 ]] && printf PASS || printf BLOCKED)"
exit "$generate_rc"
