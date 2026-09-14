#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ "$#" -eq 2 ]] || exit 1
manifest="$1"
attempt="$2"
receipt=$(mktemp -d "$attempt/signed-build-preflight.XXXXXX")
app="$attempt/build/release/Build/Products/Release/KeyRecordApp.app"
# Read-only identity inventory: no login, unlock, import, signing, or host launch.
set +e
/usr/bin/security find-identity -v -p codesigning > "$receipt/find-identity.txt" 2>&1
identity_status=$?
/usr/bin/codesign --verify --strict --verbose=2 "$app" > "$receipt/codesign-verify.txt" 2>&1
verify_status=$?
/usr/bin/codesign -d --entitlements :- --verbose=4 "$app" > "$receipt/codesign-details.txt" 2>&1
details_status=$?
/usr/bin/xcrun --find notarytool > "$receipt/notarytool.txt" 2>&1
notary_status=$?
/usr/bin/xcrun --find stapler > "$receipt/stapler.txt" 2>&1
stapler_status=$?
set -e
printf 'find_identity_exit=%s\ncodesign_verify_exit=%s\ncodesign_details_exit=%s\nnotarytool_lookup_exit=%s\nstapler_lookup_exit=%s\n' \
  "$identity_status" "$verify_status" "$details_status" "$notary_status" "$stapler_status" > "$receipt/tool-status.txt"
if /usr/bin/grep -Eq '^[[:space:]]*[0-9]+\) [[:xdigit:]]{40} ' "$receipt/find-identity.txt"; then
  reason=existing_identity_is_not_authorized_for_product_team
else
  reason=no_matching_codesigning_identity
fi
printf '%s\n' \
  'outcome=BLOCKED exit=2' "reason=$reason" "manifest=$manifest" "receipt_path=$receipt" \
  'unsigned_build_is_not_signature_evidence=true' \
  'identity_inventory_is_not_authorization=true matching_authorized_team_identity=false' \
  'codesign_team_entitlements=BLOCKED/2 signed_launch=BLOCKED/2 hosted_xctest=BLOCKED/2 runtime_spawn_count=BLOCKED/2 minimum_os_matrix=BLOCKED/2' \
  'restore=Owner-authorized Apple Developer Team ID and matching existing certificate/private key; verified internal bundle/team identity, hardened runtime and actual signed entitlements; authorized host manifest and qualified signed-launch procedure.' \
  'restore_host=Run KeyRecordAppUITests Phase1FlowTests all 7 flows; T22 system accessibility, Full Keyboard Access/Tab, VoiceOver and real screen edges; observe fresh product process tree with spawn count=1 on supported macOS14/Intel/Apple Silicon matrix.' \
  'pipeline=notarytool/stapler discovery only; retain signing/archive pipeline checkpoint; no notarization upload or public distribution.' \
  'no_host_launch_or_xctest_attempted=true' | tee "$receipt/receipt.txt"
exit 2
