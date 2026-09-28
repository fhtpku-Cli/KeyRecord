#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo 'Usage: bash Scripts/build-isolated-debug-trial.sh <trial-bundle-id> <team-id> <new-absolute-output-directory> [installed-profile-uuid]'
    echo 'Builds arm64 Debug with required trial isolation and data-protection Keychain entitlements.'
    echo 'Uses locally installed signing assets only. Does not request provisioning updates, install, or launch the App.'
    echo 'Without a profile UUID, Xcode selects a local profile automatically; with one, signing is manual.'
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
fi
if [[ "$#" -lt 3 || "$#" -gt 4 ]]; then
    usage >&2
    exit 2
fi

bundle_id="$1"
team_id="$2"
output="$3"
profile="${4:-}"
if [[ ! "$bundle_id" =~ ^com\.keyrecord\.trial\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$ ||
      ! "$team_id" =~ ^[A-Z0-9]{10}$ || "$output" != /* || -e "$output" || -L "$output" ]]; then
    echo 'Use a dedicated trial bundle ID, a ten-character Team ID, and a new absolute output directory.' >&2
    exit 2
fi
if [[ "$#" -eq 4 && ! "$profile" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
    echo 'The optional profile must be the UUID of an already installed Mac App Development profile.' >&2
    exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -m 700 "$output"
output="$(cd "$output" && pwd -P)"
signing=(CODE_SIGN_STYLE=Automatic)
if [[ -n "$profile" ]]; then
    signing=(CODE_SIGN_STYLE=Manual "PROVISIONING_PROFILE_SPECIFIER=$profile")
fi
printf 'Source commit: %s\nTrial bundle: %s\nOutput: %s\n' \
    "$(git -C "$repo_root" rev-parse HEAD)" "$bundle_id" "$output"
git -C "$repo_root" status --short

xcodebuild -project "$repo_root/KeyRecord.xcodeproj" -scheme KeyRecordApp \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$output/build" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" "DEVELOPMENT_TEAM=$team_id" \
    CODE_SIGN_IDENTITY='Apple Development' CODE_SIGNING_ALLOWED=YES \
    "INFOPLIST_FILE=$repo_root/Scripts/fixtures/isolated-debug-trial/Info.plist" \
    "CODE_SIGN_ENTITLEMENTS=$repo_root/Scripts/fixtures/isolated-debug-trial/Trial.entitlements" \
    "${signing[@]}" build 2>&1 | tee "$output/build.log"

app="$output/build/Build/Products/Debug/KeyRecordApp.app"
bash "$repo_root/Scripts/launch-isolated-debug-trial.sh" --check "$app" "$output" "$bundle_id"
printf 'Prepared App: %s\nNo App was launched; effective Keychain access and collection remain unverified.\n' "$app"
