#!/usr/bin/env bash
set -euo pipefail

base="2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-final-audit-tests.XXXXXX")"
matrix_output=/tmp/keyrecord-phase0-final-qa
owns_matrix_output=false
clean_matrix_output() {
  [[ "$owns_matrix_output" == true ]] || return
  if [[ -L "$matrix_output" ]]; then rm -f "$matrix_output"; return; fi
  [[ ! -d "$matrix_output" ]] || rm -f \
    "$matrix_output/.keyrecord-final-qa-owned" "$matrix_output/sentinel" \
    "$matrix_output/manifests-1.txt" "$matrix_output/manifests-2.txt" \
    "$matrix_output/validation-1.txt" "$matrix_output/validation-2.txt" \
    "$matrix_output/run-1.json" "$matrix_output/run-2.json" \
    "$matrix_output/normalized-1.json" "$matrix_output/normalized-2.json" \
    "$matrix_output/matrix.json" "$matrix_output/matrix.txt" \
    "$matrix_output/manifests.txt" "$matrix_output/validation.txt" \
    "$matrix_output/normalized-a.json" "$matrix_output/normalized-b.json"
  [[ ! -d "$matrix_output" ]] || rmdir "$matrix_output"
}
cleanup() { clean_matrix_output; rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM HUP

expect_exact_reject() {
  expected_status="$1"
  expected_output="$2"
  shift 2
  set +e
  actual_output="$("$@" 2>&1)"
  actual_status=$?
  set -e
  [[ "$actual_status" -eq "$expected_status" && "$actual_output" == "$expected_output" ]] || {
    printf 'unexpected rejection: status=%s output=%q expected_status=%s expected_output=%q\n' \
      "$actual_status" "$actual_output" "$expected_status" "$expected_output" >&2
    exit 1
  }
}

mkdir "$tmp_dir/bin"
cat >"$tmp_dir/bin/swift" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/bin/swift"
plan="$tmp_dir/plan.md"
: >"$plan"

if [[ -e "$matrix_output" || -L "$matrix_output" ]]; then
  marker="$matrix_output/.keyrecord-final-qa-owned"
  [[ ! -L "$matrix_output" && -d "$matrix_output" && -f "$marker" && ! -L "$marker" && "$(<"$marker")" == 'keyrecord-final-qa:v1' ]] || {
    printf 'test output occupied by non-owned path: %s\n' "$matrix_output" >&2
    exit 1
  }
  owns_matrix_output=true
  clean_matrix_output
  owns_matrix_output=false
fi

expect_exact_reject 1 'FINAL_QA=FAIL reason=arguments' env PATH="$tmp_dir/bin:$PATH" \
  bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --fixture missing --output /tmp/
expect_exact_reject 1 'FINAL_QA=FAIL reason=arguments' env PATH="$tmp_dir/bin:$PATH" \
  bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --fixture missing --output /tmp/../not-under-tmp

mkdir "$matrix_output"
owns_matrix_output=true
: >"$matrix_output/sentinel"
expect_exact_reject 1 'FINAL_QA=FAIL reason=output_not_owned' env PATH="$tmp_dir/bin:$PATH" \
  bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --output "$matrix_output"
[[ -f "$matrix_output/sentinel" ]]
clean_matrix_output
owns_matrix_output=false

mkdir "$tmp_dir/symlink-target"
ln -s "$tmp_dir/symlink-target" "$matrix_output"
owns_matrix_output=true
expect_exact_reject 1 'FINAL_QA=FAIL reason=output_symlink' env PATH="$tmp_dir/bin:$PATH" \
  bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --output "$matrix_output"
[[ -d "$tmp_dir/symlink-target" ]]
clean_matrix_output
owns_matrix_output=false

expect_exact_reject 1 'PLAN_DELIVERABLES=FAIL reason=missing_leg' \
  bash Spikes/Scripts/verify-plan-deliverables.sh "$plan" Spikes/Tests/Fixtures/FinalAudit/missing-leg
expect_exact_reject 1 $'SOURCE_BOUNDARY_AUDIT=FAIL reason=mutating_vial_api\nSpikes/Tests/Fixtures/FinalAudit/mutating-vial/VialQuery.swift:2:    case keymapWrite' \
  bash Spikes/Scripts/audit-source-boundaries.sh --fixture Spikes/Tests/Fixtures/FinalAudit/mutating-vial
expect_exact_reject 1 'ERROR privacy_forbidden_field leak.json keysequence' \
  bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --fixture Spikes/Tests/Fixtures/FinalAudit/privacy-leak --output /tmp/keyrecord-phase0-final-qa-negative
expect_exact_reject 1 'SCOPE_AUDIT=FAIL reason=out_of_scope path=Sources/KeyRecordApp/Menu.swift' \
  bash Spikes/Scripts/audit-scope.sh "$base" --fixture Spikes/Tests/Fixtures/FinalAudit/out-of-scope-ui
bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --output "$matrix_output" >/dev/null
owns_matrix_output=true
jq -e '
  .schemaVersion == 1 and .seed == "phase0-final" and (.runs | length) == 2 and
  (.runHashes | length) == 2 and .runHashes[0] == .runHashes[1] and
  all(.runs[]; .canonical.status == 0 and .canonical.result == "VALID evidence legs=57 o4=15 g0=OPEN" and
    ([.cases[].id] == ["C1","C2","C3","C4","C5"]) and
    all(.cases[]; .positive.status == 0 and .positive.result == "PASS" and
      .negative.status == 1 and .negative.result == "ERROR conclusion_recompute_mismatch"))
' "$matrix_output/matrix.json" >/dev/null
bash Spikes/Scripts/task-16-qa.sh failure >/dev/null
receipt=.omo/evidence/task-16-phase-0-validation-failure.txt
[[ "$(/usr/bin/grep -Fxc 'DOC_WRITEBACK_AUDIT=FAIL reason=unsupported_pass_or_freeze' "$receipt")" -eq 1 ]]
[[ "$(/usr/bin/grep -Fxc 'DOC_WRITEBACK_AUDIT=FAIL reason=architecture_section_whitelist' "$receipt")" -eq 1 ]]
printf 'FINAL_AUDIT_NEGATIVE_FIXTURES=PASS\n'
