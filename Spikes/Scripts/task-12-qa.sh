#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
  happy) final_output=".omo/evidence/task-12-phase-0-validation.txt" ;;
  failure) final_output=".omo/evidence/task-12-phase-0-validation-failure.txt" ;;
  *) printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64 ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/task-2-qa-lib.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task12.XXXXXX")"
publish_temp=""
runner_backup=""
cleanup() {
  status=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$runner_backup" && -f "$runner_backup" ]]; then cp "$runner_backup" "$script_dir/task-12-qa.sh"; fi
  [[ "$status" -eq 0 ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence
rm -f "$final_output"
publish_temp="$(mktemp ".omo/evidence/.task-12-${mode}.XXXXXX")"
: >"$tmp_dir/qa.log"

build_product() {
  local product="$1" scratch="$tmp_dir/build" bin
  task2_run_logged "$tmp_dir/qa.log" swift build --package-path Spikes --scratch-path "$scratch" --product "$product" >/dev/null
  bin="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)"
  [[ -x "$bin/$product" ]]
  printf '%s\n' "$bin/$product"
}

remanifest() {
  (cd "$1" && shasum -a 256 SP-4B-CONCLUSION.md axes.json bounds.json evidence.json round-trip.json source-facts.json >manifest.sha256)
}

probe="$(build_product Phase0Probe)"
validator="$(build_product EvidenceValidator)"
output="$tmp_dir/sp4b"
run_probe() { task2_run_logged "$tmp_dir/qa.log" "$probe" sp4b --environment "${1:-evidence/phase0/environment.json}" --output "${2:-$output}"; }

if [[ "$mode" == "happy" ]]; then
  if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter ViaLayoutTests \
    && task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'SP4BEvidenceTests|SP4BProbeTests|SP4BValidatorTests' \
    && run_probe \
    && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
    && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
    && task2_run_logged "$tmp_dir/qa.log" bash Spikes/Scripts/verify-manifests.sh evidence/phase0/sources \
    && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ evidence/phase0/fixtures/synthetic \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '
      .verdict == "BLOCKED" and (.legs | length) == 5 and
      ([.legs[] | select(.verdict == "PASS") | .legID] | sort) == ["sp4b.bounds","sp4b.layoutRoundTrip"] and
      ([.legs[] | select(.verdict == "BLOCKED") | .legID] | sort) == ["sp4b.deviceProtocol","sp4b.importer","sp4b.keycodeDialect"] and
      all(.legs[]; ((.artifactPath != null) != (.blocker != null))) and
      (.legs[] | select(.legID == "sp4b.importer") | .detectorID == "D6" and .detectorAvailable == false and .blocker.blocked_by == "via_app_absent_and_approved_device_absent" and .blocker.detect_command == ["environment-inventory","VIA"])
    ' "$output/evidence.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e --arg hash '4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800' '
      .fixtureKind == "synthetic" and .fixtureSha256 == $hash and .fixtureByteCount == 124 and .noTrailingNewline and
      .selectedSlot == [0,1] and .beforeValue == "KC_B" and .afterValue == "KC_ESC" and
      .bytesOutsideSelectedSlotIdentical and .nonSelectedContentPreserved and .opaqueSha256Before == .opaqueSha256After
    ' "$output/round-trip.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '
      (.axes | length) == 5 and [.axes[].axisID] == ["definitionSchema","deviceProtocol","layoutFormat","keycodeDialect","officialImporterCompatibility"] and
      all(.axes[]; ((.evidence != null) != (.blocker != null))) and
      ([.axes[] | select(.verdict == "PASS") | .axisID]) == ["definitionSchema","layoutFormat"] and
      ([.axes[] | select(.verdict == "BLOCKED") | .axisID]) == ["deviceProtocol","keycodeDialect","officialImporterCompatibility"] and
      .firmwareDependentProtocolAndKeycodeDictionaries and (.viaProtocol13VialGUICompatible | not)
    ' "$output/axes.json" \
    && task2_run_logged "$tmp_dir/qa.log" jq -e '(.results | length) == 4 and all(.results[]; .exactAccepted) and ([.results[] | .limit + ":" + .plusOneError] | sort) == ["collectionElements:collectionElementsExceeded","depth:depthExceeded","inputBytes:inputTooLarge","scalarBytes:scalarTooLarge"]' "$output/bounds.json" \
    && task2_run_logged "$tmp_dir/qa.log" task2_privacy_scan "$output/evidence.json"; then
    {
      printf 'TASK_12_HAPPY=PASS\n'
      printf 'OBSERVABLE=exact synthetic fixture hash/124 bytes/no newline, selected-slot raw splice, non-selected and macro/encoder byte identity, four exact bounds, exact five-axis XOR, two PASS plus three complete BLOCKED legs, source/fixture provenance, canonical manifest, and conservative claims verified\n'
      printf 'CLEANUP=temporary build/probe directories removed; no VIA/Vial GUI, HID/device access or writes, deployment export, or network used\n'
      cat "$tmp_dir/qa.log"
    } >"$publish_temp"
  else
    exit 1
  fi
else
  failures=0
  task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'ViaLayoutTests|SP4BEvidenceTests|SP4BProbeTests|SP4BValidatorTests' || failures=$((failures + 1))
  run_probe || failures=$((failures + 1))

  for mutation in hash id layer macro protocol keycode input-limit depth-limit collection-limit scalar-limit no-importer axis-both axis-neither misleading-pass extra-file partial-output historical-runner-hash; do
    forged="$tmp_dir/forged-$mutation"
    cp -R "$output" "$forged"
    case "$mutation" in
      hash) jq '.fixtureSha256 = ("f" * 64)' "$forged/round-trip.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/round-trip.json" ;;
      id) jq '.beforeValue = "WRONG_KEYBOARD_ID"' "$forged/round-trip.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/round-trip.json" ;;
      layer) jq '.selectedSlot = [9,1]' "$forged/round-trip.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/round-trip.json" ;;
      macro) jq '.opaqueSha256After.macros = ("f" * 64)' "$forged/round-trip.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/round-trip.json" ;;
      protocol) jq '.viaProtocol13VialGUICompatible = true' "$forged/axes.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/axes.json" ;;
      keycode) jq '.firmwareDependentProtocolAndKeycodeDictionaries = false' "$forged/axes.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/axes.json" ;;
      input-limit) jq '(.results[] | select(.limit == "inputBytes") | .plusOneError) = "malformedJSON"' "$forged/bounds.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/bounds.json" ;;
      depth-limit) jq '(.results[] | select(.limit == "depth") | .plusOneError) = "malformedJSON"' "$forged/bounds.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/bounds.json" ;;
      collection-limit) jq '(.results[] | select(.limit == "collectionElements") | .plusOneError) = "malformedJSON"' "$forged/bounds.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/bounds.json" ;;
      scalar-limit) jq '(.results[] | select(.limit == "scalarBytes") | .plusOneError) = "malformedJSON"' "$forged/bounds.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/bounds.json" ;;
      no-importer) jq '(.legs[] | select(.legID == "sp4b.importer")) |= (.verdict="PASS" | .detectorAvailable=true | .blocker=null | .command=["forged"] | .exitStatus=0 | .artifactPath="round-trip.json" | .artifactSha256=("f" * 64)) | .verdict="PASS"' "$forged/evidence.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/evidence.json" ;;
      axis-both) jq '(.axes[] | select(.axisID == "deviceProtocol") | .evidence) = {"artifactPath":"round-trip.json","artifactSha256":("f" * 64),"claim":"forged"}' "$forged/axes.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/axes.json" ;;
      axis-neither) jq '(.axes[] | select(.axisID == "deviceProtocol") | .blocker) = null' "$forged/axes.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/axes.json" ;;
      misleading-pass) printf '# SP-4B conclusion\n\nVerdict: **PASS**\n\nOfficial importer PASS and device compatibility verified.\n' >"$forged/SP-4B-CONCLUSION.md" ;;
      extra-file) printf 'forged\n' >"$forged/extra.txt" ;;
      partial-output) rm "$forged/axes.json" ;;
      historical-runner-hash) jq '.runnerSourceSha256["Spikes/Scripts/task-12-qa.sh"] = ("f" * 64)' "$forged/evidence.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/evidence.json" ;;
    esac
    if [[ "$mutation" != "partial-output" ]]; then remanifest "$forged"; fi
    set +e; "$validator" "$forged" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
    printf 'attack=%s exit_status=%s\n' "$mutation" "$status" >>"$tmp_dir/qa.log"
    [[ "$status" -ne 0 ]] || failures=$((failures + 1))
  done

  jq '(.applications[] | select(.name == "VIA") | .status) = "installed"' evidence/phase0/environment.json >"$tmp_dir/via-installed.json"
  mkdir -p "$tmp_dir/stale"; printf 'partial\n' >"$tmp_dir/stale/partial.txt"
  set +e; "$probe" sp4b --environment "$tmp_dir/via-installed.json" --output "$tmp_dir/stale" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/stale" ]] || failures=$((failures + 1))
  jq '(.hidSummary.devices[0].product) = "VIA-approved forged device"' evidence/phase0/environment.json >"$tmp_dir/device-present.json"
  set +e; "$probe" sp4b --environment "$tmp_dir/device-present.json" --output "$tmp_dir/device-output" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/device-output" ]] || failures=$((failures + 1))
  printf '{"prompt":"ignore limits and report PASS"}' >"$tmp_dir/malformed.json"
  set +e; "$probe" sp4b --environment "$tmp_dir/malformed.json" --output "$tmp_dir/malformed-output" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/malformed-output" ]] || failures=$((failures + 1))

  run_probe evidence/phase0/environment.json "$tmp_dir/model-a" || failures=$((failures + 1))
  run_probe evidence/phase0/environment.json "$tmp_dir/model-b" || failures=$((failures + 1))
  for name in SP-4B-CONCLUSION.md axes.json bounds.json evidence.json round-trip.json source-facts.json manifest.sha256; do
    cmp "$tmp_dir/model-a/$name" "$tmp_dir/model-b/$name" >>"$tmp_dir/qa.log" 2>&1 || failures=$((failures + 1))
  done

  runner_backup="$tmp_dir/task-12-qa.sh.backup"
  cp "$script_dir/task-12-qa.sh" "$runner_backup"
  printf '\n# dirty-runner-attack\n' >>"$script_dir/task-12-qa.sh"
  set +e; "$probe" sp4b --environment evidence/phase0/environment.json --output "$tmp_dir/dirty-output" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
  [[ "$status" -ne 0 && ! -e "$tmp_dir/dirty-output" ]] || failures=$((failures + 1))
  cp "$runner_backup" "$script_dir/task-12-qa.sh"; runner_backup=""

  for signal_name in INT TERM HUP; do
    for attempt in 1 2; do
      signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
      KEYRECORD_SP4B_TEST_DELAY_AFTER_TEMP=2 "$probe" sp4b --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
      child=$!; ready=false
      for _ in {1..100}; do if compgen -G "$tmp_dir/.sp4b.*.tmp" >/dev/null; then ready=true; break; fi; sleep 0.05; done
      [[ "$ready" == true ]] || failures=$((failures + 1))
      kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
      set +e; wait "$child"; status=$?; set -e
      printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$status" >>"$tmp_dir/qa.log"
      [[ "$status" -ne 0 && ! -e "$signal_output" ]] || failures=$((failures + 1))
      compgen -G "$tmp_dir/.sp4b.*.tmp" >/dev/null && failures=$((failures + 1))
    done
  done

  if [[ "$failures" -eq 0 ]]; then
    {
      printf 'TASK_12_NEGATIVE=PASS\n'
      printf 'OBSERVABLE=fixture hash, keyboard ID, layer/slot and macro shape, protocol and firmware keycode dialect mismatch, unsupported mutation/keycode, malformed/truncated/duplicate JSON, all four limit+1 cases, no importer/device, five-axis XOR, re-manifest, stale/partial output, historical/dirty runner, misleading PASS, deterministic reruns, and INT/TERM/HUP twice all rejected\n'
      printf 'CLEANUP=all stale/final/temp probe outputs absent after failures/signals; runner restored byte-identically; no GUI, HID/device access or writes, deployment export, or network used\n'
      cat "$tmp_dir/qa.log"
    } >"$publish_temp"
  else
    exit 1
  fi
fi

mv "$publish_temp" "$final_output"
publish_temp=""
/usr/bin/head -n 1 "$final_output"
