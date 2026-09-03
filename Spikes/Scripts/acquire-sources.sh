#!/usr/bin/env bash
set -euo pipefail

output="${1:-evidence/phase0/sources}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
ledger="$script_dir/source-ledger.tsv"
file_ledger="$script_dir/source-files.tsv"
clone_root="/tmp/keyrecord-phase0-sources"
stage="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-sources-output.XXXXXX")"
cleanup() { rm -rf "$clone_root" "$stage"; }
trap cleanup EXIT INT TERM HUP
rm -rf "$clone_root"
mkdir -p "$clone_root" "$stage/repos" "$stage/references"

sha256_file() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
git_blob_file() { GIT_MASTER=1 git hash-object "$1"; }
require_equal() { [[ "$1" == "$2" ]] || { printf 'provenance drift: %s expected=%s actual=%s\n' "$3" "$2" "$1" >&2; exit 1; }; }
run_network_bounded() { /usr/bin/perl -e 'alarm shift; exec @ARGV' "${KEYRECORD_FETCH_TIMEOUT_SECONDS:-180}" "$@"; }

while IFS='|' read -r name url commit tree license_path license_blob required_paths required_blobs; do
  [[ -n "$name" && "${name:0:1}" != "#" ]] || continue
  [[ "$commit" =~ ^[0-9a-f]{40}$ && "$tree" =~ ^[0-9a-f]{40}$ && "$license_blob" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'malformed pinned metadata for %s\n' "$name" >&2; exit 1;
  }
  repo="$clone_root/$name"
  run_network_bounded env GIT_MASTER=1 git clone --filter=blob:none --no-checkout "$url" "$repo"
  run_network_bounded env GIT_MASTER=1 git -C "$repo" fetch --depth 1 origin "$commit"
  GIT_MASTER=1 git -C "$repo" checkout --detach "$commit"
  require_equal "$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" "$commit" "$name commit"
  require_equal "$(GIT_MASTER=1 git -C "$repo" rev-parse 'HEAD^{tree}')" "$tree" "$name tree"
  require_equal "$(GIT_MASTER=1 git -C "$repo" rev-parse "HEAD:$license_path")" "$license_blob" "$name license blob"

  destination="$stage/repos/$name"
  mkdir -p "$destination/files" "$destination/license"
  records="$stage/$name-files.ndjson"
  : >"$records"
  IFS=';' read -r -a paths <<<"$required_paths"
  for requested in "${paths[@]}"; do
    [[ -n "$requested" ]] || continue
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      mode="$(GIT_MASTER=1 git -C "$repo" ls-tree HEAD -- "$path" | cut -d ' ' -f 1)"
      [[ "$mode" == "100644" || "$mode" == "100755" ]] || { printf 'non-regular source path rejected: %s:%s mode=%s\n' "$name" "$path" "$mode" >&2; exit 1; }
      blob="$(GIT_MASTER=1 git -C "$repo" rev-parse "HEAD:$path")"
      expected_blob="$(awk -F $'\t' -v name="$name" -v path="$path" '$1 == name && $2 == path { print $3 }' "$file_ledger")"
      [[ "$expected_blob" =~ ^[0-9a-f]{40}$ ]] || { printf 'unlisted source file rejected: %s:%s\n' "$name" "$path" >&2; exit 1; }
      require_equal "$blob" "$expected_blob" "$name immutable file blob $path"
      mkdir -p "$destination/files/$(dirname "$path")"
      GIT_MASTER=1 git -C "$repo" show "HEAD:$path" >"$destination/files/$path"
      require_equal "$(git_blob_file "$destination/files/$path")" "$blob" "$name file blob $path"
      jq -cn --arg path "$path" --arg copied "files/$path" --arg blob "$blob" --arg sha256 "$(sha256_file "$destination/files/$path")" \
        '{path:$path,copied_path:$copied,git_blob:$blob,sha256:$sha256}' >>"$records"
    done < <(GIT_MASTER=1 git -C "$repo" ls-tree -r --name-only HEAD -- "$requested")
  done

  if [[ -n "$required_blobs" ]]; then
    IFS=';' read -r -a blob_checks <<<"$required_blobs"
    for check in "${blob_checks[@]}"; do
      path="${check%%=*}"; expected="${check#*=}"
      require_equal "$(GIT_MASTER=1 git -C "$repo" rev-parse "HEAD:$path")" "$expected" "$name required blob $path"
    done
  fi

  mkdir -p "$destination/license/$(dirname "$license_path")"
  GIT_MASTER=1 git -C "$repo" show "HEAD:$license_path" >"$destination/license/$license_path"
  retrieved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -s --arg name "$name" --arg url "$url" --arg retrieved_at "$retrieved_at" --arg ref "$commit" --arg tree "$tree" \
    --arg license_path "$license_path" --arg license_copied "license/$license_path" --arg license_blob "$license_blob" \
    --arg license_sha256 "$(sha256_file "$destination/license/$license_path")" \
    '{name:$name,url:$url,retrieved_at:$retrieved_at,upstream_ref:$ref,tree:$tree,files:.,license:{path:$license_path,copied_path:$license_copied,git_blob:$license_blob,sha256:$license_sha256}}' \
    "$records" >"$destination/provenance.json"
  rm -f "$records"
done <"$ledger"

expected_file_count="$(wc -l <"$file_ledger" | tr -d ' ')"
actual_file_count="$(find "$stage/repos" -name provenance.json -exec jq '.files | length' {} + | awk '{ total += $1 } END { print total + 0 }')"
require_equal "$actual_file_count" "$expected_file_count" 'immutable source file count'

reference_urls=(
  'https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)'
  'https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()'
  'https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication'
  'https://developer.apple.com/library/archive/technotes/tn2150/_index.html'
  'https://developer.apple.com/documentation/cryptokit/aes/gcm'
  'https://developer.apple.com/documentation/cryptokit/hkdf'
  'https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly.md'
  'https://www.rfc-editor.org/rfc/rfc9106.html'
  'https://csrc.nist.gov/pubs/sp/800/38/d/final'
)
index=0
for url in "${reference_urls[@]}"; do
  index=$((index + 1)); id="reference-$(printf '%02d' "$index")"; body="$stage/references/$id.body"; metadata="$stage/references/$id.json"
  status="$(curl --silent --show-error --location --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 --output "$body" --write-out '%{http_code}' "$url" || true)"
  retrieved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$status" == "200" ]]; then
    jq -n --arg url "$url" --arg retrieved_at "$retrieved_at" --argjson http_status "$status" --arg sha256 "$(sha256_file "$body")" \
      '{url:$url,retrieved_at:$retrieved_at,http_status:$http_status,response_sha256:$sha256,status:"CAPTURED"}' >"$metadata"
  else
    rm -f "$body"
    numeric_status="${status:-0}"; [[ "$numeric_status" =~ ^[0-9]{3}$ ]] || numeric_status=0
    jq -n --arg url "$url" --arg retrieved_at "$retrieved_at" --argjson http_status "$numeric_status" \
      '{url:$url,retrieved_at:$retrieved_at,http_status:$http_status,status:"BLOCKED",blocker:{blocked_by:"primary_reference_unavailable",detect_command:["curl","--location","--max-time","60",$url],prerequisite:"HTTP 200 from the exact primary URL",unblock_action:"Retry the bounded snapshot acquisition when the primary URL is reachable"}}' >"$metadata"
  fi
done

sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
sdk_records="$stage/sdk.ndjson"; : >"$sdk_records"; mkdir -p "$stage/references/sdk/files"
sdk_headers=(
  'System/Library/Frameworks/CoreGraphics.framework/Headers/CGEvent.h'
  'System/Library/Frameworks/AppKit.framework/Headers/NSWorkspace.h'
  'System/Library/Frameworks/IOKit.framework/Headers/hidsystem/IOHIDLib.h'
  'System/Library/Frameworks/Security.framework/Headers/SecItem.h'
  'System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h'
)
for relative in "${sdk_headers[@]}"; do
  source="$sdk_path/$relative"
  if [[ -f "$source" ]]; then
    copied="files/$relative"; mkdir -p "$stage/references/sdk/files/$(dirname "$relative")"; cp "$source" "$stage/references/sdk/$copied"
    jq -cn --arg path "$relative" --arg copied "$copied" --arg sha256 "$(sha256_file "$source")" '{path:$path,copied_path:$copied,sha256:$sha256}' >>"$sdk_records"
  else
    jq -cn --arg path "$relative" '{path:$path,status:"BLOCKED",blocker:"selected SDK header is unavailable"}' >>"$sdk_records"
  fi
done
jq -s --arg sdk_path "$sdk_path" --arg retrieved_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{sdk_path:$sdk_path,retrieved_at:$retrieved_at,headers:.}' "$sdk_records" >"$stage/references/sdk/provenance.json"
rm -f "$sdk_records"

(cd "$stage" && find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done) >"$stage/manifest.sha256"
mkdir -p "$(dirname "$output")"
rm -rf "$output"
mv "$stage" "$output"
stage="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-sources-output.done.XXXXXX")"
printf 'SOURCE_ACQUISITION=PASS output=%s\n' "$output"
