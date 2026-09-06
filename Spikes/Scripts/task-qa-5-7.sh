#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/task-qa-common.sh"
if [[ "$1" == "7" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-7-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-7-phase-0-validation-failure.txt";; *) printf 'Usage: %s 7 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-7-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  output="$tmp_dir/sp3"
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter KarabinerSpikeTests \
      && task2_run_logged "$tmp_dir/qa.log" "$probe" sp3 --environment evidence/phase0/environment.json --output "$output" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        .verdict == "BLOCKED" and ([.legs[] | select(.verdict == "PASS")] | length) == 3 and
        ([.legs[] | select(.verdict == "BLOCKED")] | length) == 4 and
        ([.legs[].legID] | sort) == ["sp3.atomicity","sp3.crashRecovery","sp3.disableLatency","sp3.managedBlock","sp3.reload","sp3.schemaLint","sp3.versionSample"] and
        all(.legs[] | select(.verdict == "BLOCKED"); .detectorAvailable == false and .command == [] and .exitStatus == null and .blocker.blocked_by != "" and (.blocker.detect_command | length) > 0 and .blocker.prerequisite != "" and .blocker.unblock_action != "")
      ' "$output/evidence.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.insertPreservedOutsideBytes and .updatePreservedOutsideBytes and .clearPreservedOutsideBytes and .restorePreservedOutsideBytes and .threeRuleBatchCount == 3 and .baselineMismatchRejected and .externalEditRefused' "$output/managed-block.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.hExpect == "finishCommit" and .hBase == "markFailedNoWrite" and .external == "externalChangeRefusal" and (.crashBoundaries | length) == 8 and .automaticExternalWrite == false' "$output/recovery.json"; then
      { printf 'TASK_7_HAPPY=PASS\nOBSERVABLE=insert/update/clear/restore exact outside bytes, three-rule atomic plan, hExpect/hBase/external recovery, 8 kill boundaries, task-4 citation, 3 fixture PASS plus 4 honest BLOCKED\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  else
    failures=0
    task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'KarabinerSpikeTests|SP3ValidatorTests|Phase0ProbeTests.testSP3' || failures=$((failures + 1))
    task2_run_logged "$tmp_dir/qa.log" "$probe" sp3 --environment evidence/phase0/environment.json --output "$output" || failures=$((failures + 1))
    cp evidence/phase0/environment.json "$tmp_dir/malformed-environment.json"
    printf '{malformed' >"$tmp_dir/malformed-environment.json"
    set +e; "$probe" sp3 --environment "$tmp_dir/malformed-environment.json" --output "$output" >>"$tmp_dir/qa.log" 2>&1; malformed_status=$?; set -e
    [[ "$malformed_status" -ne 0 && ! -e "$output" ]] || failures=$((failures + 1))
    for signal_name in INT TERM HUP; do
      for attempt in 1 2; do
        signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
        KEYRECORD_SP3_TEST_DELAY_AFTER_TEMP=2 "$probe" sp3 --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
        child=$!; ready=false
        for _ in {1..100}; do if compgen -G "$tmp_dir/.sp3.*.tmp" >/dev/null; then ready=true; break; fi; sleep 0.05; done
        [[ "$ready" == true ]] || failures=$((failures + 1))
        kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
        set +e; wait "$child"; signal_status=$?; set -e
        printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$signal_status" >>"$tmp_dir/qa.log"
        [[ ! -e "$signal_output" ]] || failures=$((failures + 1))
        compgen -G "$tmp_dir/.sp3.*.tmp" >/dev/null && failures=$((failures + 1))
      done
    done
    if [[ "$failures" -eq 0 ]]; then
      { printf 'TASK_7_NEGATIVE=PASS\nOBSERVABLE=malformed schema/block, duplicate block, baseline mismatch, all kill boundaries, unknown version, external edit, remanifest forgery, stale output, and INT/TERM/HUP twice rejected without overwrite\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  mv "$publish_temp" "$final_output"; publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi

if [[ "$1" == "6" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-6-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-6-phase-0-validation-failure.txt";; *) printf 'Usage: %s 6 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-6-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  output="$tmp_dir/sp2"
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'PrivacyTransitionTests|ModifierReconstructionTests' \
      && task2_run_logged "$tmp_dir/qa.log" "$probe" sp2 --environment evidence/phase0/environment.json --output "$output" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        .verdict == "BLOCKED" and .o6Status == "OPEN" and .g0Status == "OPEN" and
        ([.legs[] | select(.verdict == "PASS")] | length) == 3 and
        ([.legs[] | select(.verdict == "BLOCKED")] | length) == 8 and
        all(.legs[]; (.verdict != "BLOCKED") or (.dataDelta == 0 and .metaDelta == 0 and .blocker.blocked_by != "" and (.blocker.detect_command | length) > 0 and .blocker.prerequisite != "" and .blocker.unblock_action != ""))
      ' "$output/evidence.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        ([.cases[] | select(.input.scenario == "known" and .observation.outcome == "bundle" and .observation.transitionDelta == {data:1,meta:1})] | length) == 1 and
        ([.cases[] | select(.input.scenario == "knownUnattributable" and .observation.outcome == "UNKNOWN" and .observation.transitionDelta == {data:1,meta:1})] | length) == 1 and
        all(.cases[] | select(.observation.outcome == "closed"); .observation.transitionDelta == {data:0,meta:0}) and
        all(.cases[] | select(.input.scenario == "tapReset" or .input.scenario == "sleepWake"); .observation.beforeTotals == .observation.afterTotals and .observation.heldTransientAfter == 0)
      ' "$output/privacy-model.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '
        .deterministicRecovery == true and (.sidedCases | length) == 20 and (.fnCases | length) == 9 and (.recoveryCases | length) == 3 and
        ([.sidedCases[].observed] | unique | sort) == ["activeSideUnknown","both","left","none","right"] and
        ([.fnCases[].observed] | unique | sort) == ["knownActive","knownNone","unknown"] and
        all(.recoveryCases[]; ([.unknownStates[]] | unique) == ["activeSideUnknown"] and ([.recoveredStates[]] | unique) == ["right"] and .fnBeforeRecovery == "unknown" and .fnAfterRecovery == "knownNone")
      ' "$output/modifier-model.json"; then
      { printf 'TASK_6_HAPPY=PASS\nOBSERVABLE=known bundle, reliably unattributable UNKNOWN, indeterminate/secure/excluded closure, all sided states, Fn confidence, deterministic recovery, 3 model PASS plus 8 honest BLOCKED, O6/G0 OPEN\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  else
    failures=0
    task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'PrivacyTransitionTests.testContradictory|PrivacyTransitionTests.testFullContext|PrivacyTransitionTests.testPaused|ModifierReconstructionTests.testReset|SP2ValidatorTests|Phase0ProbeTests.testSP2' || failures=$((failures + 1))
    task2_run_logged "$tmp_dir/qa.log" "$probe" sp2 --environment evidence/phase0/environment.json --output "$output" || failures=$((failures + 1))
    task2_run_logged "$tmp_dir/qa.log" jq -e '
      all(.legs[] | select(.verdict == "BLOCKED"); .dataDelta == 0 and .metaDelta == 0 and .detectorAvailable == false) and
      (.legs[] | select(.legID == "sp2.secureInput") | .blocker.blocked_by) == "secure_input_helper_unavailable" and
      (.legs[] | select(.legID == "sp2.sleepWake") | .blocker.blocked_by) == "noninteractive_sleep_privilege_unavailable" and
      .o6Status == "OPEN" and .g0Status == "OPEN"
    ' "$output/evidence.json" || failures=$((failures + 1))
    for signal_name in INT TERM HUP; do
      for attempt in 1 2; do
        signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
        KEYRECORD_SP2_TEST_DELAY_AFTER_TEMP=2 "$probe" sp2 --environment evidence/phase0/environment.json --output "$signal_output" >>"$tmp_dir/qa.log" 2>&1 &
        child=$!
        ready=false
        for _ in {1..100}; do
          if compgen -G "$tmp_dir/.sp2.*.tmp" >/dev/null; then ready=true; break; fi
          sleep 0.05
        done
        [[ "$ready" == true ]] || failures=$((failures + 1))
        kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
        set +e; wait "$child"; signal_status=$?; set -e
        printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$signal_status" >>"$tmp_dir/qa.log"
        [[ ! -e "$signal_output" ]] || failures=$((failures + 1))
        compgen -G "$tmp_dir/.sp2.*.tmp" >/dev/null && failures=$((failures + 1))
      done
    done
    if [[ "$failures" -eq 0 ]]; then
      { printf 'TASK_6_NEGATIVE=PASS\nOBSERVABLE=contradictory cache, unknown Secure Input, loss/reset/wake, absent safe helper, no-sudo sleep blocker, zero deltas, stale/malformed/forged evidence rejection, O6/G0 OPEN, and INT/TERM/HUP cleanup twice passed\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  mv "$publish_temp" "$final_output"
  publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi

if [[ "$1" == "5" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-5-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-5-phase-0-validation-failure.txt";; *) printf 'Usage: %s 5 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-5-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'InputObservationTests.testProductStamped|InputObservationTests.testAutoRepeat|InputObservationTests.testTapReset|InputObservationTests.testO7' \
      && task2_run_logged "$tmp_dir/qa.log" swift run --package-path Spikes Phase0Probe preflight --output "$tmp_dir/environment.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.listenEventAccess == "denied" and .guiSession.tapCreate == "denied"' "$tmp_dir/environment.json"; then
      { printf 'TASK_5_HAPPY=PASS\nOBSERVABLE=marked synthetic drop, repeat count, reset generation, O7 boundary, and safe no-prompt listen preflight passed\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  else
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter InputObservationTests \
      && task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter SP1ValidatorTests \
      && task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'Phase0ProbeTests.testSP1MalformedEnvironmentInvalidatesStaleDestination|Phase0ProbeTests.testSP1PublishesOnlyCompleteDirectory'; then
      { printf 'TASK_5_NEGATIVE=PASS\nOBSERVABLE=duplicate/missing observations, aggregate precedence, TCC/Karabiner blockers, artifact content, runner object/source binding, identity mixing/reuse, and stale-output cleanup all reject unsupported PASS; G0 OPEN\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  mv "$publish_temp" "$final_output"
  publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi
