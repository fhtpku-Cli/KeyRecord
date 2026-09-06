#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/task-qa-common.sh"
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
