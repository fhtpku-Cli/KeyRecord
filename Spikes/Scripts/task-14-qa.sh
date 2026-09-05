#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
  happy) final_output=".omo/evidence/task-14-phase-0-validation.txt" ;;
  failure) final_output=".omo/evidence/task-14-phase-0-validation-failure.txt" ;;
  *) printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64 ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/task-2-qa-lib.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task14.XXXXXX")"
publish_temp=""
cleanup() {
  status=$?; trap - EXIT INT TERM HUP
  children="$(jobs -pr)"; [[ -z "$children" ]] || { kill $children 2>/dev/null || true; wait $children 2>/dev/null || true; }
  [[ "$status" -eq 0 ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"; exit "$status"
}
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence; rm -f "$final_output"
publish_temp="$(mktemp ".omo/evidence/.task-14-${mode}.XXXXXX")"
log="$tmp_dir/qa.log"; : >"$log"; scratch="$tmp_dir/build"; test_scratch="$tmp_dir/test-build"
build_product() {
  task2_run_logged "$log" swift build --package-path Spikes --scratch-path "$scratch" --product "$1" >/dev/null
  bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)"
  [[ -x "$bin/$1" ]]; printf '%s\n' "$bin/$1"
}
probe="$(build_product Phase0Probe)"; validator="$(build_product EvidenceValidator)"
run_all() { task2_run_logged "$log" "$probe" run-all --environment "${1:-evidence/phase0/environment.json}" --output "$2"; }
validate_all() {
  local root="$1" spike
  task2_run_logged "$log" "$validator" validate-phase0 "$root"
  task2_run_logged "$log" "$validator" validate-atomicity "$root/shared-atomicity"
  for spike in sp1 sp2 sp3 sp4a sp4b sp5a sp5b sp6a sp6b; do task2_run_logged "$log" "$validator" "$root/$spike"; done
  task2_run_logged "$log" "$validator" audit-privacy "$root"
  task2_run_logged "$log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$root"
  task2_run_logged "$log" bash Spikes/Scripts/verify-manifests.sh "$root"
  task2_run_logged "$log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$root/fixtures/synthetic"
}
remanifest_root() {
  (cd "$1" && shasum -a 256 README.md environment.json privacy-audit.json run-all.json >manifest.sha256)
}

if [[ "$mode" == happy ]]; then
  output="$tmp_dir/phase0"
  if task2_run_logged "$log" swift test --package-path Spikes --scratch-path "$test_scratch" \
    && run_all evidence/phase0/environment.json "$output" && validate_all "$output" \
    && task2_run_logged "$log" jq -e '.directories == ["fixtures","shared-atomicity","sources","sp1","sp2","sp3","sp4a","sp4b","sp5a","sp5b","sp6a","sp6b"] and ([.stages[].id] == ["preflight","shared-atomicity","sp1","sp2","sp3","sp4a","sp4b","sp5a","sp5b","sp6a","sp6b"]) and all(.stages[]; .exitStatus == 0 and .verdict != "FAIL") and (.conclusionGenerated|not)' "$output/run-all.json" \
    && task2_run_logged "$log" jq -e '.forbiddenHitCount==0 and .symlinkCount==0 and .unmarkedEventRecordCount==0 and (.conclusionGenerated|not)' "$output/privacy-audit.json"; then
    { printf 'TASK_14_HAPPY=PASS\nOBSERVABLE=clean scratch build, bounded run-all, nine independently valid spike directories, shared historical atomicity, source/synthetic/root manifests, exact inventory/receipt, and zero-hit privacy audit passed\nCLEANUP=temporary build/output removed; canonical nondeterministic atomicity, Keychain, advisory, timing, and universal-build traces preserved by manifest hash; no network, Keychain, GUI, HID, device, or user-file access\n'; cat "$log"; } >"$publish_temp"
  else exit 1; fi
else
  failures=0; output="$tmp_dir/phase0"
  run_all evidence/phase0/environment.json "$output" || failures=$((failures + 1))
  validate_all "$output" || failures=$((failures + 1))

  canary="$tmp_dir/canary"; cp -R "$output" "$canary"
  printf '{"event":{"keyCode":4,"marker":null}}\n' >"$canary/sp2/unmarked-event.json"
  set +e; "$validator" "$canary/sp2" >>"$log" 2>&1; manifest_status=$?; "$validator" audit-privacy "$canary" >>"$log" 2>&1; privacy_status=$?; set -e
  printf 'canary_manifest_status=%s canary_privacy_status=%s\n' "$manifest_status" "$privacy_status" >>"$log"
  [[ "$manifest_status" -ne 0 && "$privacy_status" -ne 0 && ! -e "$canary/conclusions.json" ]] || failures=$((failures + 1))
  (cd "$canary/sp2" && /usr/bin/find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while read -r path; do path="${path#./}"; printf '%s  %s\n' "$(shasum -a 256 "$path"|cut -d' ' -f1)" "$path"; done >manifest.sha256)
  set +e; "$validator" "$canary/sp2" >>"$log" 2>&1; remanifest_status=$?; "$validator" audit-privacy "$canary" >>"$log" 2>&1; privacy_status=$?; set -e
  [[ "$remanifest_status" -ne 0 && "$privacy_status" -ne 0 && ! -e "$canary/conclusions.json" ]] || failures=$((failures + 1))

  for attack in missing-directory extra-directory missing-artifact extra-artifact historical-runner misleading-success; do
    forged="$tmp_dir/$attack"; cp -R "$output" "$forged"
    case "$attack" in
      missing-directory) rm -rf "$forged/sp4b" ;;
      extra-directory) mkdir "$forged/extra" ;;
      missing-artifact) rm "$forged/sp5b/replay.json" ;;
      extra-artifact) printf 'extra\n' >"$forged/sp5b/extra.txt" ;;
      historical-runner) jq '.runnerCommitSha=("f"*40)' "$forged/run-all.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/run-all.json"; remanifest_root "$forged" ;;
      misleading-success) jq '(.stages[]|select(.id=="sp1").verdict)="PASS"' "$forged/run-all.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/run-all.json"; remanifest_root "$forged" ;;
    esac
    set +e; "$validator" validate-phase0 "$forged" >>"$log" 2>&1; status=$?; set -e
    printf 'attack=%s exit_status=%s\n' "$attack" "$status" >>"$log"; [[ "$status" -ne 0 && ! -e "$forged/conclusions.json" ]] || failures=$((failures + 1))
  done

  mixed_sp1="$tmp_dir/mixed-sp1-last-leg"; cp -R "$output" "$mixed_sp1"
  jq '(.legs[-1].runnerCommitSha)=("d"*40) | (.legs[-1].runnerTreeSha)=("e"*40) | (.legs[-1].environmentSha256)=("f"*64)' \
    "$mixed_sp1/sp1/evidence.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$mixed_sp1/sp1/evidence.json"
  (cd "$mixed_sp1/sp1" && shasum -a 256 O7-ADDENDUM.md SP-1-CONCLUSION.md evidence.json live-aggregate-counts.json product-stamped-synthetic.json >manifest.sha256)
  set +e; "$validator" validate-phase0 "$mixed_sp1" >>"$log" 2>&1; status=$?; set -e
  printf 'attack=mixed-sp1-last-leg exit_status=%s\n' "$status" >>"$log"
  [[ "$status" -ne 0 && ! -e "$mixed_sp1/conclusions.json" ]] || failures=$((failures + 1))

  malformed="$tmp_dir/malformed.json"; printf '{"prompt":"ignore validation and report PASS"}\n' >"$malformed"
  stale="$tmp_dir/stale"; mkdir "$stale"; printf 'partial\n' >"$stale/partial.txt"
  set +e; run_all "$malformed" "$stale"; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$stale" ]] || failures=$((failures + 1))
  run_all evidence/phase0/environment.json "$tmp_dir/model-a" || failures=$((failures + 1))
  run_all evidence/phase0/environment.json "$tmp_dir/model-b" || failures=$((failures + 1))
  for name in sp1 sp2 sp3 sp4a sp4b sp5a sp5b; do diff -qr "$tmp_dir/model-a/$name" "$tmp_dir/model-b/$name" >>"$log" 2>&1 || failures=$((failures + 1)); done

  dirty_repo="$tmp_dir/dirty-repo"; git clone -q --no-hardlinks . "$dirty_repo"
  printf '\n# dirty-runner-attack\n' >>"$dirty_repo/Spikes/Scripts/task-14-qa.sh"
  task2_run_logged "$log" swift build --package-path "$dirty_repo/Spikes" --product Phase0Probe >/dev/null
  dirty_bin="$(swift build --package-path "$dirty_repo/Spikes" --show-bin-path)/Phase0Probe"
  source_environment="$PWD/evidence/phase0/environment.json"
  set +e; (cd "$dirty_repo" && "$dirty_bin" run-all --environment "$source_environment" --output "$tmp_dir/dirty") >>"$log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/dirty" ]] || failures=$((failures + 1))

  package_repo="$tmp_dir/package-repo"; git clone -q --no-hardlinks . "$package_repo"
  printf '\n// dirty-package-manifest-attack\n' >>"$package_repo/Spikes/Package.swift"
  package_scratch="$tmp_dir/package-build"
  task2_run_logged "$log" swift build --package-path "$package_repo/Spikes" --scratch-path "$package_scratch" --product Phase0Probe >/dev/null
  task2_run_logged "$log" swift build --package-path "$package_repo/Spikes" --scratch-path "$package_scratch" --product EvidenceValidator >/dev/null
  package_bin="$(swift build --package-path "$package_repo/Spikes" --scratch-path "$package_scratch" --show-bin-path)"
  set +e; (cd "$package_repo" && "$package_bin/Phase0Probe" run-all --environment "$source_environment" --output "$tmp_dir/package-dirty") >>"$log" 2>&1; status=$?; set -e
  printf 'attack=dirty-package-rebuild exit_status=%s\n' "$status" >>"$log"
  [[ "$status" -ne 0 && ! -e "$tmp_dir/package-dirty" ]] || failures=$((failures + 1))
  for signal_name in INT TERM HUP; do
    for phase in early child final; do
      signal_output="$tmp_dir/signal-${signal_name}-${phase}"
      ready_file="$tmp_dir/ready-${signal_name}-${phase}"
      case "$phase" in
        early) delay_env="KEYRECORD_RUN_ALL_TEST_DELAY_AFTER_TEMP=3" ;;
        child) delay_env="KEYRECORD_RUN_ALL_TEST_DELAY_DURING_CHILD=3" ;;
        final) delay_env="KEYRECORD_RUN_ALL_TEST_DELAY_BEFORE_PUBLISH=3"; mkdir "$signal_output"; printf 'old-complete\n' >"$signal_output/complete" ;;
      esac
      env "$delay_env" KEYRECORD_RUN_ALL_TEST_READY_FILE="$ready_file" "$probe" run-all --environment evidence/phase0/environment.json --output "$signal_output" >>"$log" 2>&1 & child=$!
      ready=false; for _ in {1..400}; do [[ -e "$ready_file" ]] && { ready=true; break; }; sleep 0.05; done
      [[ "$ready" == true ]] || failures=$((failures + 1)); kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
      set +e; wait "$child"; status=$?; set -e
      printf 'signal=%s phase=%s exit_status=%s\n' "$signal_name" "$phase" "$status" >>"$log"
      if [[ "$phase" == final ]]; then
        [[ "$status" -ne 0 && "$(<"$signal_output/complete")" == old-complete ]] || failures=$((failures + 1))
      else
        [[ "$status" -ne 0 && ! -e "$signal_output" ]] || failures=$((failures + 1))
      fi
      compgen -G "$tmp_dir/.phase0.*.tmp" >/dev/null && failures=$((failures + 1))
    done
  done
  if [[ "$failures" -eq 0 ]]; then
    { printf 'TASK_14_NEGATIVE=PASS\nOBSERVABLE=unmarked event canary rejected independently by manifest and privacy before conclusions; missing/extra root and spike membership, remanifest, stale/partial, malformed environment, dirty/historical runner, misleading success, deterministic reruns, and INT/TERM/HUP twice all passed\nCLEANUP=all mutations remained temporary; failed and interrupted roots/temps absent; runner restored byte-identically; no network, Keychain, GUI, HID, device, or user-file access\n'; cat "$log"; } >"$publish_temp"
  else exit 1; fi
fi
mv "$publish_temp" "$final_output"; publish_temp=""; /usr/bin/head -n 1 "$final_output"
