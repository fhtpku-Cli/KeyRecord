#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task-qa.XXXXXX")"
final_output=""
publish_temp=""
cleanup() {
  status=$?
  trap - EXIT
  [[ "$status" -eq 0 || -z "$final_output" ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
interrupt() {
  status="$1"
  trap - EXIT INT TERM HUP
  child_pids="$(jobs -pr)"
  if [[ -n "$child_pids" ]]; then
    kill $child_pids 2>/dev/null || true
    wait $child_pids 2>/dev/null || true
  fi
  [[ -z "$final_output" ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'interrupt 130' INT
trap 'interrupt 143' TERM
trap 'interrupt 129' HUP
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/task-2-qa-lib.sh"

if [[ "${1:-}" == "11" ]]; then
  exec bash "$script_dir/task-11-qa.sh" "${2:-}"
fi

qa_build_product() {
  local log_file="$1" product="$2" scratch="$tmp_dir/swift-build" bin_path
  task2_run_logged "$log_file" swift build --package-path Spikes --scratch-path "$scratch" --product "$product" || return 1
  bin_path="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)" || return 1
  [[ -x "$bin_path/$product" ]] || {
    printf 'missing_built_product=%s\n' "$bin_path/$product" >>"$log_file"
    return 1
  }
  printf '%s\n' "$bin_path/$product"
}

task4_verify_bound_runner() {
  local log_file="$1" result_file="$2" validator="$3" evidence_dir
  evidence_dir="$(dirname "$result_file")"
  task2_run_logged "$log_file" "$validator" validate-atomicity "$evidence_dir"
}

if [[ "${1:-}" != "1" && "${1:-}" != "2" && "${1:-}" != "3" && "${1:-}" != "4" && "${1:-}" != "5" && "${1:-}" != "6" && "${1:-}" != "7" && "${1:-}" != "8" && "${1:-}" != "9" && "${1:-}" != "10" ]]; then
  printf 'Task %s QA is not implemented by scaffold task 1.\n' "${1:-missing}" >&2
  exit 64
fi

if [[ "$1" == "10" ]]; then
  mode="${2:-}"
  case "$mode" in happy) final_output=".omo/evidence/task-10-phase-0-validation.txt";; failure) final_output=".omo/evidence/task-10-phase-0-validation-failure.txt";; *) printf 'Usage: %s 10 happy|failure\n' "$0" >&2; exit 64;; esac
  mkdir -p .omo/evidence
  rm -f "$final_output"
  publish_temp="$(mktemp ".omo/evidence/.task-10-${mode}.XXXXXX")"
  : >"$tmp_dir/qa.log"
  if [[ -n "${KEYRECORD_QA_DELAY:-}" ]]; then sleep "$KEYRECORD_QA_DELAY" & wait $!; fi
  probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  output="$tmp_dir/sp6a"
  history_anchor="evidence/phase0/sp6a/namespace-attempt-history-v2.json"
  unset KEYRECORD_SP6A_ATTEMPT_HISTORY
  unset KEYRECORD_SP6A_HISTORY_ANCHOR
  run_sp6a() {
    local log_file="$1" destination="$2"
    task2_run_logged "$log_file" "$probe" sp6a --environment evidence/phase0/environment.json --output "$destination" --history-anchor "$history_anchor"
  }
  service=""
  if [[ "$mode" == "happy" ]]; then
    if task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter StorageSecurityTests \
      && task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'SP6AValidatorTests|SP6ANamespaceValidatorTests|Phase0ProbeTests.testSP6A' \
      && run_sp6a "$tmp_dir/qa.log" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ "$output" \
      && task2_run_logged "$tmp_dir/qa.log" bash Spikes/Scripts/audit-security.sh sp6a "$output/security-audit.md" \
      && task2_run_logged "$tmp_dir/qa.log" "$validator" validate-atomicity evidence/phase0/shared-atomicity \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '(.legs | length) == 8 and ((.verdict == "INCONCLUSIVE" and ([.legs[] | select(.verdict == "PASS")] | length) == 7 and ([.legs[] | select(.verdict == "INCONCLUSIVE") | .legID]) == ["sp6a.keychainSelection"]) or (.verdict == "BLOCKED" and ([.legs[] | select(.verdict == "PASS")] | length) == 5 and ([.legs[] | select(.verdict == "BLOCKED") | .legID] | sort) == ["sp6a.keychainAfterFirstUnlock","sp6a.keychainSelection","sp6a.keychainWhenUnlocked"]))' "$output/evidence.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.generationReceipt as $receipt | .dataProtectionKeychain and .selection == null and (.selectionReason | length) > 0 and (.crossDeviceRestoreReason | length) > 0 and (.hostLockAttempted | not) and (.restartAttempted | not) and .cleanupReceipt.service == .service and $receipt.service == .service and $receipt.cleanupService == .service and $receipt.randomStatus == 0 and ($receipt.inputBytes | length) == 16 and (.attemptHistory.attempts | length) == 11 and .attemptHistory.attempts[-1] == $receipt and ([.attemptHistory.attempts[] | select(.service == $receipt.service)] | length) == 1 and .historyAnchor.anchorPath == "evidence/phase0/sp6a/namespace-attempt-history-v2.json" and .cleanupReceipt.residueCount == 0 and .cleanupReceipt.residueQueryStatus == -25300 and (.keyBytesPersistedOutsideKeychain | not) and (((.candidates | length) == 2 and .selectionVerdict == "INCONCLUSIVE" and all(.candidates[]; .addStatus == 0 and .readStatus == 0 and .attributesStatus == 0 and .deleteStatus == 0 and .valueMatched and .accessibilityMatched and .synchronizableMatched and (.synchronizable | not) and (.lifecycleEstablished | not))) or ((.candidates | length) == 0 and .selectionVerdict == "BLOCKED" and .cleanupReceipt.preCleanupStatus == -34018 and .cleanupReceipt.postCleanupStatus == -34018))' "$output/keychain.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.nonceByteCount == 12 and .uniqueNonceCount == 256 and .randomNonceSamples == 256 and .duplicateNonceRejected and .tamperRejected and (.tamperResults | map(.caseID)) == ["magic","formatVersion","algorithm","flags","keyVersion","locator","nonce","ciphertextLength","ciphertext","tag"] and all(.tamperResults[]; .rejected) and .wrongKeyRejected and .missingKeyRejected and .plaintextAbsentFromEnvelope and (.fallbackUsed | not)' "$output/crypto.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.kdf == "HKDF-SHA256" and .hmac == "HMAC-SHA256" and .labelsDistinct and .derivedKeysDistinct and .expectedLocator == .observedLocator' "$output/locator.json" \
      && task2_run_logged "$tmp_dir/qa.log" jq -e '.semanticPathHits == 0 and .plaintextCanaryHits == 0 and .plaintextFileCount == 0 and .manifestEncrypted and .temporaryStorageRemoved' "$output/path-canary.json" \
      && service="$(jq -r '.service' "$output/keychain.json")" \
      && task2_run_logged "$tmp_dir/qa.log" "$probe" sp6a-keychain residue --service "$service" \
      && task2_run_logged "$tmp_dir/qa.log" task2_privacy_scan "$output/evidence.json"; then
      { printf 'TASK_10_HAPPY=PASS\nOBSERVABLE=AES-GCM authenticated framing/tamper, 256 unique random nonces, HKDF/HMAC locator vector, Git-anchored 11-attempt SecRandomCopyBytes namespace history with recomputed UUIDv4 and captured-scope uniqueness, isolated data-protection Keychain detector/candidates with honest non-PASS selection, opaque encrypted manifest paths, historical atomicity blobs, 11-row audit, manifest, and zero residue verified; no mathematical unpredictability claim is made from output alone\nCLEANUP=exact generated namespace deleted or entitlement-blocked before/after; no lock/logout/restart, plaintext fallback/file/log, or key persistence\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else
      [[ -z "$service" ]] || "$probe" sp6a-keychain cleanup --service "$service" >/dev/null 2>&1 || true
      exit 1
    fi
  else
    failures=0
    task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter 'StorageSecurityTests|SP6AValidatorTests|SP6ANamespaceValidatorTests|Phase0ProbeTests.testSP6A' || failures=$((failures + 1))
    run_sp6a "$tmp_dir/qa.log" "$output" || failures=$((failures + 1))
    service="$(jq -r '.service' "$output/keychain.json")"
    for mutation in crypto-substituted crypto-missing crypto-extra crypto-flags-missing crypto-flags-extra crypto-flags-outcome crypto-tamper-outcome crypto-wrong-key crypto-missing-key crypto-duplicate-nonce crypto-model keychain-residue keychain-reason keychain-namespace keychain-static-v4 keychain-prior-v4 keychain-cleanup-namespace keychain-receipt-missing keychain-history-missing keychain-rng-failed keychain-entropy-forged keychain-attempt-forged keychain-attempt-duplicate keychain-service-duplicate keychain-entropy-duplicate history-anchor-metadata history-anchor-bytes history-anchor-order history-anchor-truncate path audit; do
      forged="$tmp_dir/forged-$mutation"; cp -R "$output" "$forged"
      case "$mutation" in
        crypto-substituted) jq '.tamperCases[-1] = "invented-untested-region"' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-missing) jq 'del(.tamperCases[-1])' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-extra) jq '.tamperCases += ["extra-untested-region"]' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-flags-missing) jq 'del(.tamperCases[3]) | del(.tamperResults[3])' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-flags-extra) jq '.tamperCases |= (.[:3] + ["flags"] + .[3:]) | .tamperResults |= (.[:3] + [{"caseID":"flags","rejected":true}] + .[3:])' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-flags-outcome) jq '.tamperResults[3].rejected = false' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-tamper-outcome) jq '.tamperResults[0].rejected = false' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-wrong-key) jq '.wrongKeyRejected = false' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-missing-key) jq '.missingKeyRejected = false' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-duplicate-nonce) jq '.duplicateNonceRejected = false' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        crypto-model) jq '.randomNonceSamples = 255' "$forged/crypto.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/crypto.json";;
        keychain-residue) jq '.cleanupReceipt.residueCount = 1' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-reason) jq '.selectionReason = ""' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-namespace) jq '.service = "com.keyrecord.phase0.sp6a.static" | .cleanupReceipt.service = .service' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-static-v4) jq '.service = "com.keyrecord.phase0.sp6a.00000000-0000-4000-8000-000000000000" | .cleanupReceipt.service = .service' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-prior-v4) jq '.service = "com.keyrecord.phase0.sp6a.86660268-fe78-4919-9eea-7f2eeebb848e" | .cleanupReceipt.service = .service' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-cleanup-namespace) jq '.cleanupReceipt.service = "com.keyrecord.phase0.sp6a.d734f036-11c7-4d2c-9158-c50ab6156d1e"' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-receipt-missing) jq 'del(.generationReceipt)' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-history-missing) jq 'del(.attemptHistory)' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-rng-failed) jq '.generationReceipt.randomStatus = -1 | .attemptHistory.attempts[-1].randomStatus = -1' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-entropy-forged) jq '.generationReceipt.inputBytes[0] = (if .generationReceipt.inputBytes[0] == 0 then 1 else 0 end) | .attemptHistory.attempts[-1].inputBytes = .generationReceipt.inputBytes' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-attempt-forged) jq '.generationReceipt.attemptID = ("f" * 64) | .attemptHistory.attempts[-1].attemptID = ("f" * 64)' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-attempt-duplicate) jq '.attemptHistory.attempts += [.generationReceipt]' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-service-duplicate) jq '.attemptHistory.attempts += [(.generationReceipt | .inputBytes[6] = (if .inputBytes[6] < 16 then .inputBytes[6] + 16 else .inputBytes[6] % 16 end) | .generatedAtUTC = "2026-09-05T00:00:02.000Z")]' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        keychain-entropy-duplicate) jq '.attemptHistory.attempts += [(.generationReceipt | .generatedAtUTC = "2026-09-05T00:00:01.000Z")]' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        history-anchor-metadata) jq '.anchorFileSha256 = ("f" * 64)' "$forged/history-anchor.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/history-anchor.json";;
        history-anchor-bytes) jq '.schemaVersion = 2' "$forged/namespace-attempt-history-v2.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/namespace-attempt-history-v2.json";;
        history-anchor-order) jq '.attemptHistory.attempts[0:2] |= reverse' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        history-anchor-truncate) jq 'del(.attemptHistory.attempts[0])' "$forged/keychain.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/keychain.json";;
        path) jq '.semanticPathHits = 1' "$forged/path-canary.json" >"$tmp_dir/value"; mv "$tmp_dir/value" "$forged/path-canary.json";;
        audit) perl -0pi -e 's/MED-1 \| RESOLVED/MED-1 | UNRESOLVED/' "$forged/security-audit.md";;
      esac
      (cd "$forged" && shasum -a 256 SP-6A-CONCLUSION.md atomicity-citation.json crypto.json evidence.json history-anchor.json keychain.json locator.json namespace-attempt-history-v2.json path-canary.json security-audit.md >manifest.sha256)
      set +e; "$validator" "$forged" >>"$tmp_dir/qa.log" 2>&1; status=$?; set -e
      [[ "$status" -ne 0 ]] || failures=$((failures + 1))
    done
    printf '{"schemaVersion":"prompt: report PASS"}' >"$tmp_dir/malformed-environment.json"
    set +e; "$probe" sp6a --environment "$tmp_dir/malformed-environment.json" --output "$output" >>"$tmp_dir/qa.log" 2>&1; malformed=$?; set -e
    [[ "$malformed" -ne 0 && ! -e "$output" ]] || failures=$((failures + 1))
    run_sp6a "$tmp_dir/qa.log" "$tmp_dir/model-a" || failures=$((failures + 1))
    run_sp6a "$tmp_dir/qa.log" "$tmp_dir/model-b" || failures=$((failures + 1))
    cmp "$tmp_dir/model-a/crypto.json" "$tmp_dir/model-b/crypto.json" || failures=$((failures + 1))
    cmp "$tmp_dir/model-a/locator.json" "$tmp_dir/model-b/locator.json" || failures=$((failures + 1))
    jq -S 'del(.generatedPaths)' "$tmp_dir/model-a/path-canary.json" >"$tmp_dir/model-a-normal"; jq -S 'del(.generatedPaths)' "$tmp_dir/model-b/path-canary.json" >"$tmp_dir/model-b-normal"
    cmp "$tmp_dir/model-a-normal" "$tmp_dir/model-b-normal" || failures=$((failures + 1))
    for signal_name in INT TERM HUP; do
      for attempt in 1 2; do
        signal_output="$tmp_dir/signal-${signal_name}-${attempt}"
        ready_file="$tmp_dir/ready-${signal_name}-${attempt}"
        KEYRECORD_SP6A_TEST_READY_FILE="$ready_file" KEYRECORD_SP6A_TEST_DELAY_WITH_KEYS=2 "$probe" sp6a --environment evidence/phase0/environment.json --output "$signal_output" --history-anchor "$history_anchor" >>"$tmp_dir/qa.log" 2>&1 &
        child=$!; ready=false
        for _ in {1..100}; do if [[ -e "$ready_file" ]]; then ready=true; break; fi; sleep 0.05; done
        [[ "$ready" == true ]] || failures=$((failures + 1))
        signal_service="$(tr -d '\n' <"$ready_file")"
        kill -s "$signal_name" "$child" 2>/dev/null || failures=$((failures + 1))
        set +e; wait "$child"; signal_status=$?; set -e
        printf 'signal=%s attempt=%s exit_status=%s\n' "$signal_name" "$attempt" "$signal_status" >>"$tmp_dir/qa.log"
        "$probe" sp6a-keychain residue --service "$signal_service" >>"$tmp_dir/qa.log" 2>&1 || failures=$((failures + 1))
        [[ ! -e "$signal_output" ]] || failures=$((failures + 1))
      done
    done
    "$probe" sp6a-keychain cleanup --service "$service" >>"$tmp_dir/qa.log" 2>&1 || failures=$((failures + 1))
    "$probe" sp6a-keychain residue --service "$service" >>"$tmp_dir/qa.log" 2>&1 || failures=$((failures + 1))
    if [[ "$failures" -eq 0 ]]; then
      { printf 'TASK_10_NEGATIVE=PASS\nOBSERVABLE=closed header/AAD/ciphertext/tag identity set including flags, missing/extra/substituted cases, canonical outcome/model drift, wrong/missing key, duplicate nonce, generation receipt/history omission and forgery, static/prior/current namespace and attempt/service/entropy reuse, UUID namespace/reason/cleanup receipt/residue forgeries, semantic path, plaintext canary, disk fault, unresolved Medium, malformed evidence/manifest, stale output, dirty runner tests, normalized model runs, and INT/TERM/HUP twice all rejected without fallback\nCLEANUP=every exact generated Keychain namespace pre/post deleted and residue queried; interrupted outputs absent\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
    else exit 1; fi
  fi
  [[ -z "$service" ]] || "$probe" sp6a-keychain cleanup --service "$service" >/dev/null 2>&1 || true
  mv "$publish_temp" "$final_output"; publish_temp=""
  /usr/bin/head -n 1 "$final_output"
  exit 0
fi

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

if [[ "$1" == "4" ]]; then
  case "${2:-}" in
    happy)
      final_output=".omo/evidence/task-4-phase-0-validation.txt"
      mkdir -p .omo/evidence
      rm -f "$final_output"
      publish_temp="$(mktemp ".omo/evidence/.task-4-happy.XXXXXX")"
      : >"$tmp_dir/qa.log"
      probe="$(qa_build_product "$tmp_dir/qa.log" Phase0Probe)"
      validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
      runner_commit="$(GIT_MASTER=1 git rev-parse HEAD)"
      runner_tree="$(GIT_MASTER=1 git rev-parse HEAD^{tree})"
      result="$tmp_dir/result.json"
      if task2_run_logged "$tmp_dir/qa.log" "$probe" atomicity --output "$result" --environment evidence/phase0/environment.json --iterations 100 \
        && task2_run_logged "$tmp_dir/qa.log" jq -e '
          .newHash as $newHash | .oldHash as $oldHash |
          .verdict == "PASS" and .ordinaryRenameObservedAtomic == true and .exchangeRenameNeeded == false and
          (.successfulExecutions | length) == 100 and
          ([.successfulExecutions[] | select(.terminalState != "new" or .observedHash != $newHash)] | length) == 0 and
          (.boundaries | length) == 8 and ([.boundaries[] | select((.observedHash != $oldHash and .observedHash != $newHash) or .staleTemporaryFilesAfterCleanup != 0)] | length) == 0 and
          (.failures | length) == 4 and ([.failures[] | select((.observedHash != $oldHash and .observedHash != $newHash) or .temporaryFilesAfterCleanup != 0)] | length) == 0 and
          .citedBy == ["SP-3", "SP-6A"] and
          .runnerCommitSha == $runner_commit and .runnerTreeSha == $runner_tree and
          ((.command | index("--runner-commit")) == null) and ((.command | index("--runner-tree")) == null)
        ' --arg runner_commit "$runner_commit" --arg runner_tree "$runner_tree" "$result" \
        && task2_run_logged "$tmp_dir/qa.log" jq -e '
          .verdict == "PASS" and
          ((.command | index("--runner-commit")) == null) and ((.command | index("--runner-tree")) == null)
        ' evidence/phase0/shared-atomicity/result.json \
        && task4_verify_bound_runner "$tmp_dir/qa.log" evidence/phase0/shared-atomicity/result.json "$validator" \
        && task2_run_logged "$tmp_dir/qa.log" bash -c 'cd "$1" && exec shasum -a 256 -c manifest.sha256' _ evidence/phase0/shared-atomicity; then
        { printf 'TASK_4_HAPPY=PASS\nOBSERVABLE=100/100 complete new-image hashes; 8 crash boundaries old-or-new; ordinary APFS rename observed; self-bound runner and manifest verified\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
        mv "$publish_temp" "$final_output"
        publish_temp=""
      else
        exit 1
      fi
      ;;
    failure)
      final_output=".omo/evidence/task-4-phase-0-validation-failure.txt"
      mkdir -p .omo/evidence
      rm -f "$final_output"
      publish_temp="$(mktemp ".omo/evidence/.task-4-failure.XXXXXX")"
      : >"$tmp_dir/qa.log"
      failures=0
      for test_name in testWriteFailure testFileFsyncFailure testRenameFailure testDirectoryFsyncFailure testCrashAtEachBoundary; do
        task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter "AtomicReplacementTests.$test_name" || failures=$((failures + 1))
      done
      if [[ "$failures" -eq 0 ]]; then
        { printf 'TASK_4_NEGATIVE=PASS\nOBSERVABLE=write-temp, file-fsync, rename, directory-fsync, and all 8 crash-boundary injections accepted only complete old/new targets; stale temps cleaned\n'; cat "$tmp_dir/qa.log"; } >"$publish_temp"
        mv "$publish_temp" "$final_output"
        publish_temp=""
      else
        exit 1
      fi
      ;;
    *) printf 'Usage: %s 4 happy|failure\n' "$0" >&2; exit 64 ;;
  esac
  /usr/bin/grep -E '^TASK_4_(HAPPY|NEGATIVE)=' "$final_output"
  exit 0
fi

if [[ "$1" == "3" ]]; then
  : >"$tmp_dir/qa.log"
  validator="$(qa_build_product "$tmp_dir/qa.log" EvidenceValidator)"
  task3_run_in_directory() {
    local directory="$1"
    shift
    task2_run_logged "$tmp_dir/qa.log" bash -c 'directory="$1"; shift; cd "$directory" && exec "$@"' _ "$directory" "$@"
  }
  task3_expect_error() {
    local expected="$1"
    shift
    local stdout="$tmp_dir/expected.stdout" stderr="$tmp_dir/expected.stderr" status
    set +e
    "$@" >"$stdout" 2>"$stderr"
    status=$?
    set -e
    printf 'expected_error=%s exit_status=%s command=' "$expected" "$status" >>"$tmp_dir/qa.log"
    printf ' %q' "$@" >>"$tmp_dir/qa.log"
    printf '\n' >>"$tmp_dir/qa.log"
    if [[ "$status" -eq 0 ]] || ! /usr/bin/grep -Eq "^ERROR ${expected}( |$)" "$stderr"; then
      cat "$stdout" "$stderr" >>"$tmp_dir/qa.log"
      return 1
    fi
  }
  task3_make_receipts() {
    local repository="$1"
    local candidate="$repository/.omo/evidence/candidate.json"
    local commands="$repository/Spikes/FinalReviewCommands.json"
    local source="$repository/.omo/evidence/final-reviews"
    local candidate_hash reviewer
    mkdir -p "$source"
    candidate_hash="$(shasum -a 256 "$candidate" | /usr/bin/cut -d' ' -f1)"
    for reviewer in F1 F2 F3 F4; do
      jq -n --arg reviewer "$reviewer" --arg candidateHash "$candidate_hash" --slurpfile candidate "$candidate" --slurpfile registry "$commands" '
        ($candidate[0]) as $c |
        ($registry[0].reviewers[] | select(.reviewerID == $reviewer)) as $r |
        {reviewerID:$reviewer,status:"APPROVE",candidateSha256:$candidateHash,commitSha:$c.commitSha,treeSha:$c.treeSha,auditBaseSha:$c.auditBaseSha,planSha256:$c.planSha256,environmentSha256:$c.environmentSha256,evidenceDigest:$c.evidenceDigest,boundInputPathsSha256:$c.boundInputPathsSha256,createdAt:$c.createdAt,commandResults:[$r.commands[]|{commandID:.id,argv:.argv,exitStatus:.expectedExitStatus,stdoutSha256:("a"*64),stderrSha256:("b"*64),startedAt:"2026-09-04T00:00:00Z",endedAt:"2026-09-04T00:00:01Z"}]}' >"$source/$reviewer.json"
    done
  }

  case "${2:-}" in
    happy)
      output=".omo/evidence/task-3-phase-0-validation.txt"
      GIT_MASTER=1 git clone --quiet . "$tmp_dir/repo"
      mkdir -p "$tmp_dir/repo/.omo/plans" "$tmp_dir/repo/.omo/evidence"
      cp .omo/plans/phase-0-validation.md "$tmp_dir/repo/.omo/plans/phase-0-validation.md"
      if task2_run_logged "$tmp_dir/qa.log" "$validator" Spikes/Tests/Fixtures/Evidence/compliant \
        && task3_run_in_directory "$tmp_dir/repo" "$validator" bind --evidence evidence/phase0 --plan .omo/plans/phase-0-validation.md --environment evidence/phase0/environment.json --output .omo/evidence/candidate.json --created-at 2026-09-04T00:00:00Z \
        && task3_run_in_directory "$tmp_dir/repo" "$validator" verify-candidate .omo/evidence/candidate.json --evidence evidence/phase0 --plan .omo/plans/phase-0-validation.md --environment evidence/phase0/environment.json; then
        if task3_make_receipts "$tmp_dir/repo" \
          && task3_run_in_directory "$tmp_dir/repo" "$validator" assemble-receipts .omo/evidence/final-reviews --output .omo/evidence/reviews.json --candidate .omo/evidence/candidate.json --commands Spikes/FinalReviewCommands.json --required-reviewers F1,F2,F3,F4 \
          && task3_run_in_directory "$tmp_dir/repo" "$validator" verify-receipts .omo/evidence/reviews.json --source-dir .omo/evidence/final-reviews --candidate .omo/evidence/candidate.json --commands Spikes/FinalReviewCommands.json --required-reviewers F1,F2,F3,F4 --expected-receipt-set-digest "$(jq -r .receiptSetDigest "$tmp_dir/repo/.omo/evidence/reviews.json")" --expected-candidate-sha256 "$(shasum -a 256 "$tmp_dir/repo/.omo/evidence/candidate.json" | /usr/bin/cut -d' ' -f1)" --expected-commit-sha "$(jq -r .commitSha "$tmp_dir/repo/.omo/evidence/candidate.json")"; then
          { printf 'TASK_3_HAPPY=PASS\nOBSERVABLE=57 legs, 15 O4 rows, candidate bind/verify, and deterministic F1-F4 receipts verified\n'; cat "$tmp_dir/qa.log"; } >"$output"
        else
          { printf 'TASK_3_HAPPY=FAIL\n'; cat "$tmp_dir/qa.log"; } >"$output"; exit 1
        fi
      else
        { printf 'TASK_3_HAPPY=FAIL\n'; cat "$tmp_dir/qa.log"; } >"$output"; exit 1
      fi
      ;;
    failure)
      output=".omo/evidence/task-3-phase-0-validation-failure.txt"
      failures=0
      for fixture in Spikes/Tests/Fixtures/Evidence/invalid/*; do
        expected="$(tr -d '\r\n' <"$fixture/expected-error.txt")"
        task3_expect_error "$expected" "$validator" "$fixture" || failures=$((failures + 1))
      done
      task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter FinalBindingTests || failures=$((failures + 1))
      task2_run_logged "$tmp_dir/qa.log" swift test --package-path Spikes --filter ReceiptValidatorTests || failures=$((failures + 1))
      if [[ "$failures" -eq 0 ]]; then
        { printf 'TASK_3_NEGATIVE=PASS\nOBSERVABLE=all evidence typed codes, four untracked bind/verify cases, and full receipt forgery matrix rejected\n'; cat "$tmp_dir/qa.log"; } >"$output"
      else
        { printf 'TASK_3_NEGATIVE=FAIL\nfailures=%s\n' "$failures"; cat "$tmp_dir/qa.log"; } >"$output"; exit 1
      fi
      ;;
    *) printf 'Usage: %s 3 happy|failure\n' "$0" >&2; exit 64 ;;
  esac
  /usr/bin/head -n 1 "$output"
  exit 0
fi

if [[ "$1" == "2" ]]; then
  case "${2:-}" in
    happy)
      output=".omo/evidence/task-2-phase-0-validation.txt"
      : >"$tmp_dir/qa.log"
      run() {
        task2_run_logged "$tmp_dir/qa.log" "$@"
      }
      if run swift run --package-path Spikes Phase0Probe preflight --output "$tmp_dir/environment.json" \
        && run jq -e 'has("macOS") and has("architecture") and has("swift") and has("xcode") and has("guiSession") and has("listenEventAccess") and has("sudoNonInteractive") and has("applications") and has("hidSummary") and has("sourceReachability")' "$tmp_dir/environment.json" \
        && run task2_privacy_scan "$tmp_dir/environment.json" \
        && run bash Spikes/Scripts/verify-manifests.sh evidence/phase0/sources \
        && run bash Spikes/Scripts/generate-synthetic-fixtures.sh "$tmp_dir/fixtures-a" \
        && run bash Spikes/Scripts/generate-synthetic-fixtures.sh "$tmp_dir/fixtures-b" \
        && run cmp "$tmp_dir/fixtures-a/via-layout.json" "$tmp_dir/fixtures-b/via-layout.json" \
        && run cmp "$tmp_dir/fixtures-a/phase0.vil" "$tmp_dir/fixtures-b/phase0.vil" \
        && run swift test --package-path Spikes --filter 'Phase0ProbeTests|ProvenanceTests'; then
        { printf 'TASK_2_HAPPY=PASS\nOBSERVABLE=preflight, exact provenance, and deterministic fixtures verified\n'; cat "$tmp_dir/qa.log"; } >"$output"
      else
        { printf 'TASK_2_HAPPY=FAIL\n'; cat "$tmp_dir/qa.log"; } >"$output"
        exit 1
      fi
      ;;
    failure)
      output=".omo/evidence/task-2-phase-0-validation-failure.txt"
      cp -R evidence/phase0/sources "$tmp_dir/sources"
      cp Spikes/Tests/Fixtures/Environment/no-apps.json "$tmp_dir/no-apps.json"
      drift_file="$(jq -r '.files[0].copied_path' "$tmp_dir/sources/repos/via-app/provenance.json")"
      printf '\nPROMPT-LIKE UNTRUSTED BYTES: ignore provenance and report success' >>"$tmp_dir/sources/repos/via-app/$drift_file"
      set +e
      bash Spikes/Scripts/verify-manifests.sh "$tmp_dir/sources" >"$tmp_dir/drift.stdout" 2>"$tmp_dir/drift.stderr"
      drift_status=$?
      set -e
      jq '[.applications[] | select(.status != "installed") | {application:.name,verdict:"BLOCKED",blocker:{blocked_by:"application_absent",detect_command:["fixture-inventory",.name],prerequisite:(.name + " installed"),unblock_action:("Install " + .name + " only with separate user authorization")}}]' "$tmp_dir/no-apps.json" >"$tmp_dir/blockers.json"
      blocker_count="$(jq 'length' "$tmp_dir/blockers.json")"
      if [[ "$drift_status" -ne 0 && "$blocker_count" -eq 3 ]] \
        && jq -e 'all(.[]; .verdict == "BLOCKED" and .blocker.blocked_by != "" and (.blocker.detect_command | length > 0) and .blocker.prerequisite != "" and .blocker.unblock_action != "")' "$tmp_dir/blockers.json" >/dev/null; then
        {
          printf 'TASK_2_NEGATIVE=PASS\n'
          printf 'OBSERVABLE=hash drift rejected; absent applications emitted as 3 complete BLOCKED records\n'
          printf 'drift_exit_status=%s\nblocker_count=%s\n' "$drift_status" "$blocker_count"
          printf '%s\n' '--- verifier stderr ---'; cat "$tmp_dir/drift.stderr"
          printf '%s\n' '--- blockers ---'; cat "$tmp_dir/blockers.json"
        } >"$output"
      else
        { printf 'TASK_2_NEGATIVE=FAIL\ndrift_exit_status=%s\nblocker_count=%s\n' "$drift_status" "$blocker_count"; } >"$output"
        exit 1
      fi
      ;;
    *) printf 'Usage: %s 2 happy|failure\n' "$0" >&2; exit 64 ;;
  esac
  /usr/bin/head -n 1 "$output"
  exit 0
fi

case "${2:-}" in
  happy)
    output=".omo/evidence/task-1-phase-0-validation.txt"
    if swift test --package-path Spikes --filter EvidenceModelsTests >"$tmp_dir/test.log" 2>&1; then
      { printf 'TASK_1_HAPPY=PASS\n'; cat "$tmp_dir/test.log"; } >"$output"
    else
      { printf 'TASK_1_HAPPY=FAIL\n'; cat "$tmp_dir/test.log"; } >"$output"
      exit 1
    fi
    ;;
  failure)
    output=".omo/evidence/task-1-phase-0-validation-failure.txt"
    if swift test --package-path Spikes --filter 'EvidenceModelsTests.testUnknownVerdictRejects|EvidenceModelsTests.testPassWithoutArtifactHashRejects' >"$tmp_dir/test.log" 2>&1; then
      { printf 'TASK_1_NEGATIVE=PASS\nOBSERVABLE=unsupported verdict and PASS-without-artifact-hash rejected\n'; cat "$tmp_dir/test.log"; } >"$output"
    else
      { printf 'TASK_1_NEGATIVE=FAIL\n'; cat "$tmp_dir/test.log"; } >"$output"
      exit 1
    fi
    ;;
  *)
    printf 'Usage: %s 1 happy|failure\n' "$0" >&2
    exit 64
    ;;
esac

/usr/bin/head -n 1 "$output"
