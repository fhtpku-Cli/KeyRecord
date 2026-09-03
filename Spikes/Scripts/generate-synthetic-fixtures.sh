#!/usr/bin/env bash
set -euo pipefail
output="${1:-evidence/phase0/fixtures/synthetic}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-fixtures.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM HUP

printf '%s' '{"name":"phase0-layout","vendorProductId":1980457056,"layers":[["KC_A","KC_B"],["KC_C","KC_D"]],"macros":[""],"encoders":[]}' >"$tmp_dir/via-layout.json"
printf '%s' '{"version":1,"uid":"0000000000000000","layout":[["KC_A","KC_B"]],"encoder_layout":[],"layout_options":0,"macro":[""],"vial_protocol":6,"via_protocol":9,"tap_dance":[],"combo":[],"key_override":[],"alt_repeat_key":[],"settings":{}}' >"$tmp_dir/phase0.vil"

[[ "$(shasum -a 256 "$tmp_dir/via-layout.json" | cut -d ' ' -f 1)" == '4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800' ]]
[[ "$(shasum -a 256 "$tmp_dir/phase0.vil" | cut -d ' ' -f 1)" == '61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3' ]]
[[ "$(tail -c 1 "$tmp_dir/via-layout.json" | od -An -tuC | tr -d ' ')" != '10' ]]
[[ "$(tail -c 1 "$tmp_dir/phase0.vil" | od -An -tuC | tr -d ' ')" != '10' ]]

cat >"$tmp_dir/provenance.json" <<'JSON'
{"evidenceKind":"synthetic","generator":"Spikes/Scripts/generate-synthetic-fixtures.sh","files":[{"path":"via-layout.json","sha256":"4f08c8457b0bbf7001e2245a7b139cf0f225f6e9e8ecf210e23c5c6c45b55800"},{"path":"phase0.vil","sha256":"61a93eac2421c9cbe1b0f81625f3d01f3ca9443645b4d9ba86c1f5237af633b3"}]}
JSON
cat >"$tmp_dir/README.md" <<'README'
# Approved synthetic fixtures

Only deterministic, privacy-reviewed fixtures may be committed here. Do not store real keystreams, text, event sequences, exact event timestamps, credentials, device serial numbers, or user configuration.
README
(cd "$tmp_dir" && shasum -a 256 README.md phase0.vil provenance.json via-layout.json >manifest.sha256)
mkdir -p "$(dirname "$output")"
rm -rf "$output"
mv "$tmp_dir" "$output"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-fixtures.done.XXXXXX")"
printf 'SYNTHETIC_FIXTURES=PASS output=%s\n' "$output"
