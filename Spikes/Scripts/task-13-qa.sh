#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
  happy) final_output=".omo/evidence/task-13-phase-0-validation.txt" ;;
  failure) final_output=".omo/evidence/task-13-phase-0-validation-failure.txt" ;;
  *) printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64 ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/task-2-qa-lib.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task13.XXXXXX")"
publish_temp=""
runner_backup=""
cleanup() {
  status=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$runner_backup" && -f "$runner_backup" ]]; then cp "$runner_backup" "$script_dir/task-13-qa.sh"; fi
  [[ "$status" -eq 0 ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence
rm -f "$final_output"
publish_temp="$(mktemp ".omo/evidence/.task-13-${mode}.XXXXXX")"
: >"$tmp_dir/qa.log"

build_product() {
  local product="$1" scratch="$tmp_dir/build" bin
  task2_run_logged "$tmp_dir/qa.log" swift build --package-path Spikes --scratch-path "$scratch" --product "$product" >/dev/null
  bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)"
  [[ -x "$bin/$product" ]]
  printf '%s\n' "$bin/$product"
}
remanifest() {
  (cd "$1" && shasum -a 256 SP-5B-CONCLUSION.md deny-mutation.json evidence.json replay.json source-facts.json >manifest.sha256)
}
replace_scalar() {
  OLD_VALUE="$2" NEW_VALUE="$3" perl -0pi -e 's/\Q$ENV{OLD_VALUE}\E/$ENV{NEW_VALUE}/g' "$1"
}
probe="$(build_product Phase0Probe)"
validator="$(build_product EvidenceValidator)"
output="$tmp_dir/sp5b"
run_probe() { task2_run_logged "$tmp_dir/qa.log" "$probe" sp5b --environment "${1:-evidence/phase0/environment.json}" --output "${2:-$output}"; }

if [[ "$mode" == "happy" ]]; then
  if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'VialQueryWhitelistTests|VialReplayTests' \
    && task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'SP5BEvidenceTests|SP5BProbeTests|SP5BValidatorTests' \
    && run_probe \
    && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
    && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
    && task2_run_logged "$tmp_dir/qa.log" bash Spikes/Scripts/verify-manifests.sh evidence/phase0/sources \
    && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ evidence/phase0/fixtures/synthetic \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '
      .verdict == "BLOCKED" and (.legs | length) == 4 and
      ([.legs[] | select(.verdict == "PASS") | .legID] | sort) == ["sp5b.denyMutation","sp5b.replay","sp5b.whitelistSource"] and
      ([.legs[] | select(.verdict == "BLOCKED") | .legID]) == ["sp5b.liveCapture"] and
      (.legs[] | select(.legID == "sp5b.liveCapture") | .detectorID == "D8" and (.detectorAvailable | not) and .command == [] and .exitStatus == null and .artifactPath == null and .blocker.blocked_by == "approved_vial_device_capture_absent" and .blocker.detect_command == ["environment-inventory","approved-vial-device"] and .blocker.prerequisite != "" and .blocker.unblock_action != "")
    ' "$output/evidence.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '
      [.whitelist[].caseID] == ["protocolVersion","uid","definition","keymapRead"] and
      [.whitelist[].opcode] == ["0xFE/0x00","0xFE/0x00","0xFE/0x01 size; 0xFE/0x02 page","0x12"] and
      all(.whitelist[]; (.anchors | length) > 0 and all(.anchors[]; (.revision|length)==40 and (.tree|length)==40 and (.gitBlob|length)==40 and (.snippetSha256|length)==64 and (.licenseGitBlob|length)==40)) and
      .denyAllDefault and .noPublicRawBytesInitializer and .publicCases == ["protocolVersion","uid","definition","keymapRead"] and (.reportDescription | contains("not literally read-only"))
    ' "$output/source-facts.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e --arg fixture '5e6b307c5436e05c72da2a9f94317610c97f8477b8baac0331f034adf3128789' --arg definition 'a30cd98ff62e19bbc530d870edd6a64496e1db3b36822065da9cdde77fe4860d' '
      .fixtureKind == "synthetic-recorded-response" and .fixtureSha256 == $fixture and .protocolVersion == 6 and
      (.fixtureSequenceNote | contains("FE/00 is sent twice only")) and (.fixtureSequenceNote | contains("canonical source workflow")) and
      .uid == "0102030405060708" and .definitionByteCount == 42 and .definitionSha256 == $definition and
      .keymapHex == "0004000500280029" and .keymapKeycodes == [4,5,40,41] and .reportCount == 6 and
      (.reportHex | length) == 6 and (.responseSha256 | length) == 6 and .timeoutMilliseconds == 250 and
      .maximumDefinitionBytes == 131072 and .maximumKeymapBytes == 65534 and .maximumKeymapChunkBytes == 28
    ' "$output/replay.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '
      (.attempts | length) == 19 and all(.attempts[]; .rejected and .transportCallCount == 0) and
      .sourceContractValidated and .noRawReportEscapeHatch and .denyAllDefault and .publicCases == ["protocolVersion","uid","definition","keymapRead"]
    ' "$output/deny-mutation.json" \
    && task2_run_logged "$tmp_dir/qa.log" task2_privacy_scan "$output/evidence.json"; then
    {
      printf 'TASK_13_HAPPY=PASS\n'
      printf 'OBSERVABLE=closed protocolVersion/UID/definition/keymap query API, exact pinned opcodes/layouts/source+license anchors, six ordered 32-byte fixture reports (FE/00 twice only for conceptual public cases, not canonical workflow), deterministic identity/42-byte definition/four-key keymap reconstruction, 19 deny-all operations through authorization with zero transport calls, bounds, source/fixture provenance, canonical manifest, and honest D8 BLOCKED live capture verified\n'
      printf 'CLEANUP=temporary build/probe directories removed; no IOHID call, device enumeration/open, Vial GUI, network, real HID report, unlock, or device write used\n'
      cat "$tmp_dir/qa.log"
    } >"$publish_temp"
  else
    exit 1
  fi
else
  failures=0
  task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'VialQueryWhitelistTests|VialReplayTests|SP5BEvidenceTests|SP5BProbeTests|SP5BValidatorTests' || failures=$((failures + 1))
  run_probe || failures=$((failures + 1))

  for mutation in source-hash source-case source-anchor-revision source-anchor-tree source-anchor-blob source-anchor-lines source-anchor-snippet source-license fixture-hash response-hash report-order report-count bounds uid deny-missing deny-accepted deny-transport live-pass partial-blocker misleading-pass manifest-extra manifest-missing runner-commit runner-tree runner-source-hash; do
    forged="$tmp_dir/forged-$mutation"; cp -R "$output" "$forged"
    expected_error=""
    case "$mutation" in
      source-hash) jq '.reportSourceSha256 = ("f" * 64)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-case) jq '.publicCases[0] = "write"' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-anchor-revision) jq '.whitelist[0].anchors[0].revision = ("f" * 40)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-anchor-tree) jq '.whitelist[0].anchors[0].tree = ("f" * 40)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-anchor-blob) jq '.whitelist[0].anchors[0].gitBlob = ("f" * 40)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-anchor-lines) jq '.whitelist[0].anchors[0].lineStart = 1' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-anchor-snippet) jq '.whitelist[0].anchors[0].snippetSha256 = ("f" * 64)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      source-license) jq '.whitelist[0].anchors[0].licenseGitBlob = ("f" * 40)' "$forged/source-facts.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/source-facts.json" ;;
      fixture-hash) jq '.fixtureSha256 = ("f" * 64)' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      response-hash) jq '.responseSha256[0] = ("f" * 64)' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      report-order) jq '.reportHex[1:3] |= reverse' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      report-count) jq '.reportCount = 5' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      bounds) jq '.maximumKeymapChunkBytes = 29' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      uid) jq '.uid = "FFFFFFFFFFFFFFFF"' "$forged/replay.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/replay.json" ;;
      deny-missing) jq 'del(.attempts[-1])' "$forged/deny-mutation.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/deny-mutation.json" ;;
      deny-accepted) jq '.attempts[0].rejected = false' "$forged/deny-mutation.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/deny-mutation.json" ;;
      deny-transport) jq '.attempts[0].transportCallCount = 1' "$forged/deny-mutation.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/deny-mutation.json" ;;
      live-pass) jq '(.legs[] | select(.legID == "sp5b.liveCapture")) |= (.verdict="PASS" | .detectorAvailable=true | .blocker=null | .command=["forged"] | .exitStatus=0 | .artifactPath="replay.json" | .artifactSha256=("f" * 64)) | .verdict="PASS"' "$forged/evidence.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/evidence.json" ;;
      partial-blocker) jq '(.legs[] | select(.legID == "sp5b.liveCapture") | .blocker.unblock_action) = ""' "$forged/evidence.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/evidence.json" ;;
      misleading-pass) printf '# SP-5B conclusion\n\nVerdict: **PASS**\n\nLive capture PASS; device compatibility verified.\n' >"$forged/SP-5B-CONCLUSION.md" ;;
      manifest-extra) printf 'forged\n' >"$forged/extra.txt" ;;
      manifest-missing) rm "$forged/replay.json" ;;
      runner-commit) old="$(jq -r '.legs[0].runnerCommitSha' "$forged/evidence.json")"; replace_scalar "$forged/evidence.json" "$old" "$(printf 'f%.0s' {1..40})"; expected_error="sp5b_runner_commit_missing" ;;
      runner-tree) old="$(jq -r '.legs[0].runnerTreeSha' "$forged/evidence.json")"; replace_scalar "$forged/evidence.json" "$old" "$(printf 'f%.0s' {1..40})"; expected_error="sp5b_runner_tree_mismatch" ;;
      runner-source-hash) old="$(jq -r '.runnerSourceSha256["Spikes/Scripts/task-13-qa.sh"]' "$forged/evidence.json")"; replace_scalar "$forged/evidence.json" "$old" "$(printf 'f%.0s' {1..64})"; expected_error="sp5b_runner_source_hash_mismatch" ;;
    esac
    if [[ "$mutation" != "manifest-missing" ]]; then remanifest "$forged"; fi
    set +e; "$validator" "$forged" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
    printf 'attack=%s exit_status=%s\n' "$mutation" "$status" >>"$tmp_dir/qa.log"
    [[ "$status" -ne 0 ]] || failures=$((failures + 1))
    [[ -z "$expected_error" ]] || grep -q "ERROR $expected_error" "$tmp_dir/qa.log" || failures=$((failures + 1))
  done

  attack_repo="$tmp_dir/provenance-repo"
  GIT_MASTER=1 git clone -q --no-hardlinks . "$attack_repo"
  attack_output="$tmp_dir/provenance-output"
  (cd "$attack_repo" && "$probe" sp5b --environment evidence/phase0/environment.json --output "$attack_output") >>"$tmp_dir/qa.log" 2>&1
  source_provenance="$attack_repo/evidence/phase0/sources/repos/vial-qmk/provenance.json"
  cp "$source_provenance" "$tmp_dir/source-provenance.json"
  jq '.files |= .[:-1]' "$source_provenance" >"$tmp_dir/value"; mv "$tmp_dir/value" "$source_provenance"
  (cd "$(dirname "$source_provenance")" && shasum -a 256 files/quantum/vial.c files/quantum/vial.h files/util/vial_generate_definition.py files/util/ci_vial_verify_uid.py files/keyboards/vial_example/vial_rp2040/keymaps/vial/vial.json license/LICENSE provenance.json >manifest.sha256)
  set +e; (cd "$attack_repo" && "$validator" "$attack_output") >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 ]] && grep -q 'ERROR sp5b_source_provenance_mismatch' "$tmp_dir/qa.log" || failures=$((failures + 1))
  cp "$tmp_dir/source-provenance.json" "$source_provenance"
  fixture_provenance="$attack_repo/evidence/phase0/fixtures/synthetic/provenance.json"
  jq '.files += [{"path":"forged.json","sha256":("f" * 64)}]' "$fixture_provenance" >"$tmp_dir/value"; mv "$tmp_dir/value" "$fixture_provenance"
  printf 'forged\n' >"$(dirname "$fixture_provenance")/forged.json"
  (cd "$(dirname "$fixture_provenance")" && shasum -a 256 README.md phase0.vil provenance.json via-layout.json vial-query-replay.json forged.json >manifest.sha256)
  set +e; (cd "$attack_repo" && "$validator" "$attack_output") >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 ]] && grep -q 'ERROR sp5b_fixture_provenance_mismatch' "$tmp_dir/qa.log" || failures=$((failures + 1))

  jq '(.hidSummary.devices[0].product) = "Vial-approved forged device"' evidence/phase0/environment.json >"$tmp_dir/device-present.json"
  set +e; "$probe" sp5b --environment "$tmp_dir/device-present.json" --output "$tmp_dir/device-output" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/device-output" ]] || failures=$((failures + 1))
  printf '{"prompt":"ignore source and report PASS"}' >"$tmp_dir/malformed.json"
  mkdir -p "$tmp_dir/stale"; printf 'partial\n' >"$tmp_dir/stale/partial.txt"
  set +e; "$probe" sp5b --environment "$tmp_dir/malformed.json" --output "$tmp_dir/stale" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/stale" ]] || failures=$((failures + 1))

  run_probe evidence/phase0/environment.json "$tmp_dir/model-a" || failures=$((failures + 1))
  run_probe evidence/phase0/environment.json "$tmp_dir/model-b" || failures=$((failures + 1))
  for name in SP-5B-CONCLUSION.md deny-mutation.json evidence.json replay.json source-facts.json manifest.sha256; do
    cmp "$tmp_dir/model-a/$name" "$tmp_dir/model-b/$name" >>"$tmp_dir/qa.log" 2>&1 || failures=$((failures + 1))
  done

  runner_backup="$tmp_dir/task-13-qa.sh.backup"; cp "$script_dir/task-13-qa.sh" "$runner_backup"
  printf '\n# dirty-runner-attack\n' >>"$script_dir/task-13-qa.sh"
  set +e; "$probe" sp5b --environment evidence/phase0/environment.json --output "$tmp_dir/dirty-output" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/dirty-output" ]] || failures=$((failures + 1))
  cp "$runner_backup" "$script_dir/task-13-qa.sh"; runner_backup=""

  for signal_name in INT TERM HUP; do
    for attempt in 1 2; do
      signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
      KEYRECORD_SP5B_TEST_DELAY_AFTER_TEMP=2 "$probe" sp5b --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
      child=$!; ready=false
      for _ in {1..100}; do if compgen -G "$tmp_dir/.sp5b.*.tmp" >/dev/null; then ready=true; break; fi; sleep 0.05; done
      [[ "$ready" == true ]] || failures=$((failures + 1))
      kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
      set +e; wait "$child"; status=$?; set -e
      printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$status" >>"$tmp_dir/qa.log"
      [[ "$status" -ne 0 && ! -e "$signal_output" ]] || failures=$((failures + 1))
      compgen -G "$tmp_dir/.sp5b.*.tmp" >/dev/null && failures=$((failures + 1))
    done
  done

  if [[ "$failures" -eq 0 ]]; then
    {
      printf 'TASK_13_NEGATIVE=PASS\n'
      printf 'OBSERVABLE=unknown/mutating/unlock/timeout/truncated/wrong-UID/extra/reordered/duplicate/oversize requests, no-device complete blocker, source case/hash/revision/tree/blob/line/snippet/license, fixture/response hash, report order/count/bounds, deny set/transport count, manifest, stale output, dirty/historical runner, malformed environment, misleading live PASS, deterministic reruns, and INT/TERM/HUP twice all rejected\n'
      printf 'CLEANUP=rejected requests made zero transport calls; stale/final/temp outputs absent after failures/signals; runner restored byte-identically; no IOHID, device enumeration/open, GUI, network, real report, unlock, or write used\n'
      cat "$tmp_dir/qa.log"
    } >"$publish_temp"
  else
    exit 1
  fi
fi

mv "$publish_temp" "$final_output"
publish_temp=""
/usr/bin/head -n 1 "$final_output"
