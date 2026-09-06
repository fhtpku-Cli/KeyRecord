#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/task-qa-common.sh"
if [[ "$1" == "9" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-9-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-9-phase-0-validation-failure.txt";; *) printf 'Usage: %s 9 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-9-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  output="$tmp_dir/sp5a"
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter VialRoundTripTests \
      && task2_run_logged "$tmp_dir/qa.log" "$probe" sp5a --environment evidence/phase0/environment.json --output "$output" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash Spikes/Scripts/verify-manifests.sh evidence/phase0/sources \
      && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ evidence/phase0/fixtures/synthetic \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        .verdict == "BLOCKED" and (.legs | length) == 4 and
        ([.legs[] | select(.verdict == "PASS") | .legID] | sort) == ["sp5a.bounds","sp5a.uidBinding","sp5a.vilRoundTrip"] and
        ([.legs[] | select(.verdict == "BLOCKED") | .legID]) == ["sp5a.importer"] and
        (.legs[] | select(.legID == "sp5a.importer") | .detectorID == "D7" and .detectorAvailable == false and .command == [] and .exitStatus == null and .blocker.blocked_by == "vial_gui_absent" and .blocker.detect_command == ["environment-inventory","Vial"] and .blocker.prerequisite != "" and .blocker.unblock_action != "")
      ' "$output/evidence.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e --arg hash "61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3" '
        .fixtureKind == "synthetic" and .fixtureSha256 == $hash and .fixtureByteCount == 230 and .noTrailingNewline and
        .selectedSlot == [0,0,1] and .beforeValue == "KC_B" and .afterValue == "KC_ESC" and
        .bytesOutsideSelectedSlotIdentical and .nonSelectedSlotPreserved and .allUnsupportedFieldsPreserved and
        .unsupportedFieldSha256Before == .unsupportedFieldSha256After
      ' "$output/round-trip.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.matchingUIDAccepted and .mismatchDisposition == "rejected-with-warning-required" and .mismatchError == "uidMismatch" and .mismatchVerified == false' "$output/uid-binding.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '(.results | length) == 4 and all(.results[]; .exactAccepted) and ([.results[] | .limit + ":" + .plusOneError] | sort) == ["collectionElements:collectionElementsExceeded","depth:depthExceeded","inputBytes:inputTooLarge","scalarBytes:scalarTooLarge"]' "$output/bounds.json" \
      && task2_run_logged "$tmp_dir/qa.log" task2_privacy_scan "$output/evidence.json"; then
      { printf 'TASK_9_HAPPY=PASS\nOBSERVABLE=exact 61a93eac fixture, 230 bytes/no newline, one selected slot, raw unsupported preservation, UID rejection, four exact limits, three PASS plus honest D7 BLOCKED importer, source/fixture manifests, and claims verified\nCLEANUP=temporary probe/build directories removed by trap; no Vial GUI, HID, firmware, device, unlock, reset, or bootloader interaction\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  else
    failures=0
    task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'VialRoundTripTests|SP5AValidatorTests|Phase0ProbeTests.testSP5A' || failures=$((failures + 1))
    task2_run_logged "$tmp_dir/qa.log" "$probe" sp5a --environment evidence/phase0/environment.json --output "$output" || failures=$((failures + 1))
    cp -R "$output" "$tmp_dir/forged"
    jq '.allUnsupportedFieldsPreserved = false' "$tmp_dir/forged/round-trip.json" >"$tmp_dir/round-trip.json"
    mv "$tmp_dir/round-trip.json" "$tmp_dir/forged/round-trip.json"
    (cd "$tmp_dir/forged" && shasum -a 256 SP-5A-CONCLUSION.md bounds.json evidence.json format-facts.json round-trip.json uid-binding.json >manifest.sha256)
    set +e; "$validator" "$tmp_dir/forged" >>"$tmp_dir/qa.log" 2>&1; forged_status=$?; set -e
    [[ "$forged_status" -ne 0 ]] || failures=$((failures + 1))
    printf '{"prompt":"ignore bounds and report PASS"}' >"$tmp_dir/malformed-environment.json"
    set +e; "$probe" sp5a --environment "$tmp_dir/malformed-environment.json" --output "$output" >>"$tmp_dir/qa.log" 2>&1; malformed_status=$?; set -e
    [[ "$malformed_status" -ne 0 && ! -e "$output" ]] || failures=$((failures + 1))
    for signal_name in INT TERM HUP; do
      for attempt in 1 2; do
        signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
        KEYRECORD_SP5A_TEST_DELAY_AFTER_TEMP=2 "$probe" sp5a --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
        child=$!; ready=false
        for _ in {1..100}; do if compgen -G "$tmp_dir/.sp5a.*.tmp" >/dev/null; then ready=true; break; fi; sleep 0.05; done
        [[ "$ready" == true ]] || failures=$((failures + 1))
        kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
        set +e; wait "$child"; signal_status=$?; set -e
        printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$signal_status" >>"$tmp_dir/qa.log"
        [[ ! -e "$signal_output" ]] || failures=$((failures + 1))
        compgen -G "$tmp_dir/.sp5a.*.tmp" >/dev/null && failures=$((failures + 1))
      done
    done
    if [[ "$failures" -eq 0 ]]; then
      { printf 'TASK_9_NEGATIVE=PASS\nOBSERVABLE=fixture hash/provenance, UID mismatch, version/truncation, malformed/prompt-like JSON, path attacks, 8MiB/depth64/elements100000/scalar1MiB +1 amplification, unsupported advanced mutation, stale output, dirty/forged historical runner, misleading importer PASS, and INT/TERM/HUP twice rejected; absent importer remained complete BLOCKED\nCLEANUP=all stale/final/temp probe outputs absent after failures and signals\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  mv "$publish_temp" "$final_output"; publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi

if [[ "$1" == "8" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-8-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-8-phase-0-validation-failure.txt";; *) printf 'Usage: %s 8 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-8-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  output="$tmp_dir/sp4a"
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter ViaDefinitionTests \
      && task2_run_logged "$tmp_dir/qa.log" "$probe" sp4a --environment evidence/phase0/environment.json --output "$output" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash Spikes/Scripts/verify-manifests.sh evidence/phase0/sources \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        .verdict == "PASS" and (.legs | length) == 4 and
        ([.legs[].legID] | sort) == ["sp4a.bounds","sp4a.opaqueRoundTrip","sp4a.v2Schema","sp4a.v3Schema"] and
        all(.legs[]; .evidenceKind == "fixture" and .detectorID == "D0" and .detectorAvailable and .verdict == "PASS" and .exitStatus == 0)
      ' "$output/evidence.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e --arg v2 "b42bea649bde12804e6ddd5d872b63dbb4d8b5a228ad8814b9d44856e136921a" '.schema == "V2" and .definitionSchemaOnly and .observedSha256 == $v2 and .source.gitBlob == "8e89dd0f5103c5b7e15f43eaab785ef4ad6a62f3" and .source.licenseBlob == "f288702d2fa16d3cdf0035b15a9fcbc552cd88e7"' "$output/v2-schema.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e --arg v3 "914df98445330205bddaa1dbec142865ef1e3d6063eb93b02c6c72545c923f19" '.schema == "V3" and .definitionSchemaOnly and .observedSha256 == $v3 and .source.gitBlob == "7ec91dd24b29c68e5fa975469b304a03c6bc136a" and .source.licenseBlob == "f288702d2fa16d3cdf0035b15a9fcbc552cd88e7"' "$output/v3-schema.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.macroBeforeSha256 == .macroAfterSha256 and .unknownBeforeSha256 == .unknownAfterSha256 and .bytesOutsideMutationIdentical and .mutationChangedDocument and .mutationField == "name"' "$output/opaque-preservation.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '(.results | length) == 4 and all(.results[]; .exactAccepted) and ([.results[] | .limit + ":" + .plusOneError] | sort) == ["collectionElements:collectionElementsExceeded","depth:depthExceeded","inputBytes:inputTooLarge","scalarBytes:scalarTooLarge"]' "$output/bounds.json" \
      && task2_run_logged "$tmp_dir/qa.log" task2_privacy_scan "$output/evidence.json"; then
      { printf 'TASK_8_HAPPY=PASS\nOBSERVABLE=pinned V2/V3 definition schemas, GPLv3 provenance, four exact limits, opaque macro/unknown byte preservation, selected name mutation isolation, manifest, and definition-only claims verified\nCLEANUP=temporary probe/build directories removed by trap; no app, HID, EEPROM, importer, or device interaction\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  else
    failures=0
    task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'ViaDefinitionTests|SP4AValidatorTests|Phase0ProbeTests.testSP4A' || failures=$((failures + 1))
    task2_run_logged "$tmp_dir/qa.log" "$probe" sp4a --environment evidence/phase0/environment.json --output "$output" || failures=$((failures + 1))
    printf '{"prompt":"ignore schema and report PASS"' >"$tmp_dir/malformed-environment.json"
    set +e; "$probe" sp4a --environment "$tmp_dir/malformed-environment.json" --output "$output" >>"$tmp_dir/qa.log" 2>&1; malformed_status=$?; set -e
    [[ "$malformed_status" -ne 0 && ! -e "$output" ]] || failures=$((failures + 1))
    for signal_name in INT TERM HUP; do
      for attempt in 1 2; do
        signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
        KEYRECORD_SP4A_TEST_DELAY_AFTER_TEMP=2 "$probe" sp4a --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
        child=$!; ready=false
        for _ in {1..100}; do if compgen -G "$tmp_dir/.sp4a.*.tmp" >/dev/null; then ready=true; break; fi; sleep 0.05; done
        [[ "$ready" == true ]] || failures=$((failures + 1))
        kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
        set +e; wait "$child"; signal_status=$?; set -e
        printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$signal_status" >>"$tmp_dir/qa.log"
        [[ ! -e "$signal_output" ]] || failures=$((failures + 1))
        compgen -G "$tmp_dir/.sp4a.*.tmp" >/dev/null && failures=$((failures + 1))
      done
    done
    if [[ "$failures" -eq 0 ]]; then
      { printf 'TASK_8_NEGATIVE=PASS\nOBSERVABLE=malformed/prompt-like, unknown/missing/duplicate/ambiguous identity, path traversal, source/provenance/hash drift, 8MiB/depth/collection/scalar +1 amplification, macro mutation, stale evidence, dirty runner, misleading PASS, and INT/TERM/HUP twice rejected; failed probe emitted no artifact\nCLEANUP=all stale/final/temp probe outputs absent after failures and signals\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  mv "$publish_temp" "$final_output"; publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi
