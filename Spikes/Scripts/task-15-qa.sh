#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
  happy) receipt=".omo/evidence/task-15-phase-0-validation.txt" ;;
  failure) receipt=".omo/evidence/task-15-phase-0-validation-failure.txt" ;;
  *) printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64 ;;
esac

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task15.XXXXXX")"
publish_temp=""
cleanup() {
  status=$?
  trap - EXIT INT TERM HUP
  jobs -pr | xargs kill 2>/dev/null || true
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence
rm -f "$receipt"
publish_temp="$(mktemp ".omo/evidence/.task-15-${mode}.XXXXXX")"
log="$tmp_dir/qa.log"
: >"$log"

run() { printf '+ ' >>"$log"; printf '%q ' "$@" >>"$log"; printf '\n' >>"$log"; "$@" >>"$log" 2>&1; }
scratch="$tmp_dir/build"
run swift build --package-path Spikes --scratch-path "$scratch" --product EvidenceValidator
bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)/EvidenceValidator"

source_root="evidence/phase0"
source_commit=""
generator_commit=""
committed_conclusions=""
committed_hash_before=""
if [[ -f "$source_root/conclusions.json" ]]; then
  committed_conclusions="$source_root/conclusions.json"
  committed_hash_before="$(shasum -a 256 "$committed_conclusions" | cut -d ' ' -f 1)"
  source_commit="$(jq -r '.source_evidence_commit_sha' "$source_root/conclusions.json")"
  generator_commit="$(jq -r '.generator_commit_sha' "$source_root/conclusions.json")"
  mkdir -p "$tmp_dir/raw-source"
  GIT_MASTER=1 git archive "$source_commit" evidence/phase0 | tar -x -C "$tmp_dir/raw-source"
  source_root="$tmp_dir/raw-source/evidence/phase0"
fi
[[ -n "$source_commit" ]] || source_commit="$(GIT_MASTER=1 git rev-parse HEAD)"
[[ -n "$generator_commit" ]] || generator_commit="$(GIT_MASTER=1 git rev-parse HEAD)"
source_commit="$(GIT_MASTER=1 git rev-parse --verify "$source_commit^{commit}")"
generator_commit="$(GIT_MASTER=1 git rev-parse --verify "$generator_commit^{commit}")"

generate() {
  args=(generate-conclusions --source "$source_root" --output "$1")
  args+=(--source-commit "$source_commit" --generator-commit "$generator_commit")
  if [[ "${KEYRECORD_CONCLUSION_TEST_SIGNAL_EXEC:-}" == 1 ]]; then exec "$bin" "${args[@]}"; fi
  "$bin" "${args[@]}"
}
validate() { "$bin" "$1"; }
check_committed_conclusions() {
  [[ -z "$committed_conclusions" ]] && return
  if ! run validate "$committed_conclusions"; then return 1; fi
  local hash_after
  hash_after="$(shasum -a 256 "$committed_conclusions" | cut -d ' ' -f 1)"
  [[ "$hash_after" == "$committed_hash_before" ]]
}

if [[ "$mode" == happy ]]; then
  run bash Spikes/Scripts/verify-manifests.sh evidence/phase0
  check_committed_conclusions
  run generate "$tmp_dir/first"
  run generate "$tmp_dir/second"
  run validate "$tmp_dir/first"
  run validate "$tmp_dir/second"
  hash1="$(shasum -a 256 "$tmp_dir/first/conclusions.json" | cut -d ' ' -f 1)"
  hash2="$(shasum -a 256 "$tmp_dir/second/conclusions.json" | cut -d ' ' -f 1)"
  [[ "$hash1" == "$hash2" ]]
  run cmp "$tmp_dir/first/conclusions.json" "$tmp_dir/second/conclusions.json"
  [[ -z "$committed_conclusions" ]] || run cmp "$committed_conclusions" "$tmp_dir/first/conclusions.json"
  run bash Spikes/Scripts/verify-manifests.sh "$tmp_dir/first"
  run "$bin" audit-privacy "$tmp_dir/first"
  run jq -e '([.spikes[].id] | sort) == ["SP-1","SP-2","SP-3","SP-4A","SP-4B","SP-5A","SP-5B","SP-6A","SP-6B"] and ([.o_items[].id] | sort) == ["O1","O2","O3","O4","O5","O6","O7"] and ((.spikes[] | select(.id == "SP-6B") | .dependency_frozen) == false)' "$tmp_dir/first/conclusions.json"
  run jq -e '([.o4_matrix[].id] | sort) == (["karabiner.configSchema","karabiner.managedBlock","karabiner.atomicReplace","karabiner.reload","karabiner.disableLatency","via.definitionSchema","via.deviceProtocol","via.layoutBackupFormat","via.keycodeDialect","via.officialImporterCompatibility","vial.definitionSchema","vial.deviceProtocol","vial.layoutBackupFormat","vial.keycodeDialect","vial.officialImporterCompatibility"] | sort) and ([.o4_matrix[] | ((has("evidence_path") and (has("blocked_ref")|not)) or (has("blocked_ref") and (has("evidence_path")|not)))] | all) and .g0.status == "OPEN" and (.downstream_blocks | length) >= 5' "$tmp_dir/first/conclusions.json"
  check_committed_conclusions
  { printf 'TASK_15_HAPPY=PASS\nCONCLUSIONS_SHA256=%s\nDETERMINISTIC_SHA256=%s\n' "$committed_hash_before" "$hash2"; cat "$log"; } >"$publish_temp"
else
  run generate "$tmp_dir/canonical"
  canonical_hash="$(shasum -a 256 "$tmp_dir/canonical/conclusions.json" | cut -d ' ' -f 1)"
  failures=0
  mutations=(missing-spike extra-spike missing-o extra-o missing-o4 extra-o4 missing-downstream extra-downstream xor-both xor-neither evidence-path evidence-hash blocker-ref vial-substitution g0-passed o6-closed sp6b-frozen compatibility rerun-drift manifest-rebind abbreviated-source abbreviated-generator abbreviated-runner duplicate-root duplicate-nested stale partial)
  for mutation in "${mutations[@]}"; do
    copy="$tmp_dir/$mutation"; cp -R "$tmp_dir/canonical" "$copy"
    file="$copy/conclusions.json"
    case "$mutation" in
      missing-spike) jq 'del(.spikes[0])' "$file" >"$tmp_dir/value" ;;
      extra-spike) jq '.spikes += [.spikes[0]]' "$file" >"$tmp_dir/value" ;;
      missing-o) jq 'del(.o_items[0])' "$file" >"$tmp_dir/value" ;;
      extra-o) jq '.o_items += [.o_items[0]]' "$file" >"$tmp_dir/value" ;;
      missing-o4) jq 'del(.o4_matrix[0])' "$file" >"$tmp_dir/value" ;;
      extra-o4) jq '.o4_matrix += [.o4_matrix[0]]' "$file" >"$tmp_dir/value" ;;
      missing-downstream) jq 'del(.downstream_blocks[0])' "$file" >"$tmp_dir/value" ;;
      extra-downstream) jq '.downstream_blocks += [.downstream_blocks[0]]' "$file" >"$tmp_dir/value" ;;
      xor-both) jq '.o4_matrix[0].evidence_path="sp3/evidence.json" | .o4_matrix[0].evidence_sha256=("f"*64)' "$file" >"$tmp_dir/value" ;;
      xor-neither) jq 'del(.o4_matrix[0].blocked_ref)' "$file" >"$tmp_dir/value" ;;
      evidence-path) jq '.spikes[0].evidence.path="sp2/evidence.json"' "$file" >"$tmp_dir/value" ;;
      evidence-hash) jq '.spikes[0].evidence.sha256=("f"*64)' "$file" >"$tmp_dir/value" ;;
      blocker-ref) jq '.o4_matrix[0].blocked_ref="sp3.reload"' "$file" >"$tmp_dir/value" ;;
      vial-substitution) jq --arg hash "$(shasum -a 256 "$copy/sp5a/bounds.json" | cut -d ' ' -f 1)" '(.o4_matrix[] | select(.id=="vial.definitionSchema")) |= (.evidence_path="sp5a/bounds.json" | .evidence_sha256=$hash)' "$file" >"$tmp_dir/value" ;;
      g0-passed) jq '.g0.status="PASSED" | .g0.blocking_leg_ids=[] | .g0.candidate_selection="session"' "$file" >"$tmp_dir/value" ;;
      o6-closed) jq '(.o_items[] | select(.id=="O6") | .status)="RESOLVED"' "$file" >"$tmp_dir/value" ;;
      sp6b-frozen) jq '(.spikes[] | select(.id=="SP-6B") | .dependency_frozen)=true' "$file" >"$tmp_dir/value" ;;
      compatibility) jq '.spikes[4].limitations=["official importer compatible"]' "$file" >"$tmp_dir/value" ;;
      rerun-drift) jq '.spikes[0].rerun_argv[0]="false"' "$file" >"$tmp_dir/value" ;;
      manifest-rebind) jq '.source_root_manifest_sha256=("f"*64)' "$file" >"$tmp_dir/value" ;;
      abbreviated-source) jq '.source_evidence_commit_sha=(.source_evidence_commit_sha[0:7])' "$file" >"$tmp_dir/value" ;;
      abbreviated-generator) jq '.generator_commit_sha=(.generator_commit_sha[0:7])' "$file" >"$tmp_dir/value" ;;
      abbreviated-runner) jq '.spikes[0].runner_commit_sha=(.spikes[0].runner_commit_sha[0:7])' "$file" >"$tmp_dir/value" ;;
      duplicate-root) perl -0pe 's/^\{/\{"schema_version":1,/' "$file" >"$tmp_dir/value" ;;
      duplicate-nested) perl -0pe 's/"evidence":\{/"evidence":{"path":"sp1\/evidence.json",/' "$file" >"$tmp_dir/value" ;;
      stale) printf '{}\n' >"$tmp_dir/value" ;;
      partial) printf '{"schema_version":1' >"$tmp_dir/value" ;;
    esac
    mv "$tmp_dir/value" "$file"
    (cd "$copy" && { for name in README.md environment.json privacy-audit.json run-all.json conclusions.json SP-*-CONCLUSION.md; do shasum -a 256 "$name"; done; } | LC_ALL=C sort -k3 >manifest.sha256)
    set +e; validate "$copy" >>"$log" 2>&1; status=$?; set -e
    [[ "$status" -ne 0 ]] || failures=$((failures + 1))
  done
  coordinated="$tmp_dir/coordinated-source"
  cp -R "$source_root" "$coordinated"
  jq '.coordinated_extra=true' "$coordinated/sp1/evidence.json" >"$tmp_dir/value"
  mv "$tmp_dir/value" "$coordinated/sp1/evidence.json"
  (cd "$coordinated/sp1" && { for name in *; do [[ "$name" == manifest.sha256 ]] || shasum -a 256 "$name"; done; } | LC_ALL=C sort -k3 >manifest.sha256)
  (cd "$coordinated" && shasum -a 256 README.md environment.json privacy-audit.json run-all.json | LC_ALL=C sort -k3 >manifest.sha256)
  set +e
  "$bin" generate-conclusions --source "$coordinated" --source-commit "$source_commit" --output "$tmp_dir/coordinated-output" >>"$log" 2>&1
  coordinated_status=$?
  set -e
  [[ "$coordinated_status" -ne 0 && ! -e "$tmp_dir/coordinated-output" ]] || failures=$((failures + 1))
  dirty="$tmp_dir/dirty-clone"; GIT_MASTER=1 git clone -q --no-hardlinks . "$dirty"
  generate "$tmp_dir/dirty-valid" >>"$log" 2>&1
  printf '\n' >>"$dirty/Spikes/Sources/EvidenceValidator/ConclusionValidator.swift"
  set +e; (cd "$dirty" && "$bin" "$tmp_dir/dirty-valid") >>"$log" 2>&1; dirty_status=$?; set -e
  [[ "$dirty_status" -ne 0 ]] || failures=$((failures + 1))
  for signal_name in INT TERM HUP; do
    for attempt in 1 2; do
      output="$tmp_dir/signal-$signal_name-$attempt"
      ready="$tmp_dir/ready-$signal_name-$attempt"
      KEYRECORD_CONCLUSION_TEST_SIGNAL_EXEC=1 KEYRECORD_CONCLUSION_TEST_DELAY=30 KEYRECORD_CONCLUSION_TEST_READY_FILE="$ready" generate "$output" >>"$log" 2>&1 & child=$!
      observed=false
      for _ in {1..600}; do [[ -f "$ready" ]] && { observed=true; break; }; sleep 0.05; done
      [[ "$observed" == true ]] || failures=$((failures + 1))
      candidate="$(cat "$ready" 2>/dev/null || true)"
      [[ -n "$candidate" && -e "$candidate" ]] || failures=$((failures + 1))
      kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
      set +e; wait "$child"; signal_status=$?; set -e
      case "$signal_name" in INT) expected_status=130 ;; TERM) expected_status=143 ;; HUP) expected_status=129 ;; esac
      printf 'signal=%s attempt=%s ready=%s exit_status=%s expected_status=%s\n' "$signal_name" "$attempt" "$observed" "$signal_status" "$expected_status" >>"$log"
      [[ "$signal_status" -eq "$expected_status" && ! -e "$output" && ! -e "$candidate" ]] || failures=$((failures + 1))
    done
  done
  [[ "$(shasum -a 256 "$tmp_dir/canonical/conclusions.json" | cut -d ' ' -f 1)" == "$canonical_hash" ]] || failures=$((failures + 1))
  check_committed_conclusions || failures=$((failures + 1))
  if [[ "$failures" -ne 0 ]]; then
    printf 'TASK_15_NEGATIVE=FAIL failures=%s\n' "$failures" >&2
    exit 1
  fi
  { printf 'TASK_15_NEGATIVE=PASS\nCANONICAL_SHA256=%s\nMUTATIONS=%s\nSIGNAL_ATTEMPTS=6\n' "$committed_hash_before" "${#mutations[@]}"; cat "$log"; } >"$publish_temp"
fi

mv "$publish_temp" "$receipt"
publish_temp=""
/usr/bin/head -n 1 "$receipt"
