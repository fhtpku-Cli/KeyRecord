#!/usr/bin/env bash
set -euo pipefail

mode=launch
if [[ "${1:-}" == --check ]]; then
    mode=check
    shift
fi
if [[ "$#" != 3 ]]; then
    printf 'Usage: %s [--check] /absolute/Trial.app /absolute/private-root trial-keychain-namespace\n' "$0" >&2
    exit 2
fi

app="$1"
root="$2"
namespace="$3"
if [[ "$app" != /* || "$root" != /* || ! -d "$app" || ! -d "$root" ]]; then
    printf '%s\n' 'App and private root must be existing absolute directories.' >&2
    exit 2
fi
app="$(cd "$app" && pwd -P)"
root="$(cd "$root" && pwd -P)"
plist="$app/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")"
trial_required="$(/usr/libexec/PlistBuddy -c 'Print :KeyRecordRequiresTrialIsolation' "$plist")"
if [[ "$bundle_id" != com.keyrecord.trial.* || -z "$display_name" || "$trial_required" != true ]]; then
    printf '%s\n' 'Bundle must have a distinct trial ID, display name, and required-isolation marker.' >&2
    exit 2
fi
if [[ "$namespace" == com.keyrecord.app || ! "$namespace" =~ ^[A-Za-z0-9.-]{1,128}$ ]]; then
    printf '%s\n' 'Invalid trial Keychain namespace.' >&2
    exit 2
fi
/usr/bin/codesign --verify --strict --deep "$app"

# A valid signature alone does not make the data-protection Keychain usable.
# A trial built and then re-signed without its application-identifier entitlement
# passed codesign verification but failed SecItemAdd with -34018 on first consent.
signed_team="$(/usr/bin/codesign -dv --verbose=2 "$app" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
entitlements="$(/usr/bin/codesign -d --entitlements - "$app" 2>/dev/null)"
if [[ -z "$signed_team" || "$signed_team" == 'not set' ||
      "$entitlements" != *'com.apple.application-identifier'* ||
      "$entitlements" != *"$signed_team.$bundle_id"* ]]; then
    printf '%s\n' 'Trial signature lacks its matching data-protection Keychain application identifier.' >&2
    exit 2
fi

printf 'Trial identity: %s (%s)\n' "$display_name" "$bundle_id"
if [[ "$mode" == check ]]; then
    printf '%s\n' 'Launch inputs verified; no app was started.'
    exit 0
fi

exec /usr/bin/env -u CFFIXED_USER_HOME /usr/bin/open -n -W -a "$app" \
    --env 'KEYRECORD_LOCAL_CAPTURE=1' \
    --env "KEYRECORD_TRIAL_STORE=$root/store" \
    --env "KEYRECORD_TRIAL_NAMESPACE=$namespace" \
    --env "KEYRECORD_PRIVACY_INTERVAL_PATH=$root/privacy-interval.jsonl" \
    --env "KEYRECORD_DIAGNOSTIC_SUMMARY_PATH=$root/summary.json"
