#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script_dir="$(cd "$(dirname "$0")" && pwd)"
probe_src="$repo_root/Spikes/.build/release/Phase0Probe"
helper_src="$repo_root/Spikes/.build/release/keyrecord-secure-input-status"
install_dir="/usr/local/libexec"
probe_dst="$install_dir/keyrecord-phase0-probe"
helper_dst="$install_dir/keyrecord-secure-input-status"
app_dst="/Applications/KeyRecord-Phase0-Probe.app"
app_probe="$app_dst/Contents/MacOS/keyrecord-phase0-probe"
plist_src="$script_dir/KeyRecord-Phase0-Probe.app/Contents/Info.plist"

[[ -x "$probe_src" ]] || { echo "missing probe: $probe_src (run: swift build --package-path Spikes -c release)" >&2; exit 1; }
[[ -x "$helper_src" ]] || { echo "missing helper: $helper_src (run: swift -O Spikes/Scripts/keyrecord-secure-input-status.swift -o Spikes/.build/release/keyrecord-secure-input-status)" >&2; exit 1; }
[[ -f "$plist_src" ]] || { echo "missing app plist: $plist_src" >&2; exit 1; }

sudo mkdir -p "$install_dir"
sudo install -m 755 "$probe_src" "$probe_dst"
sudo install -m 755 "$helper_src" "$helper_dst"

sudo mkdir -p "$app_dst/Contents/MacOS"
sudo install -m 755 "$probe_src" "$app_probe"
sudo install -m 644 "$plist_src" "$app_dst/Contents/Info.plist"
sudo codesign --force --sign - --identifier com.keyrecord.phase0.probe "$app_probe"
sudo codesign --force --sign - "$app_dst"

echo "INSTALLED probe=$probe_dst"
echo "INSTALLED app=$app_probe"
echo "INSTALLED helper=$helper_dst"
echo "INPUT_MONITORING=grant KeyRecord-Phase0-Probe.app in System Settings (not the bare libexec binary)"
"$helper_dst" --once
