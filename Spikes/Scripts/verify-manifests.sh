#!/usr/bin/env bash
set -euo pipefail

root="${1:-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
ledger="$script_dir/source-ledger.tsv"
file_ledger="$script_dir/source-files.tsv"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-manifests.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM HUP

[[ -d "$root" && -f "$root/manifest.sha256" ]] || { printf 'source manifest root is missing: %s\n' "$root" >&2; exit 1; }

if [[ -d "$root/sources" ]]; then
  printf '%s\n' fixtures shared-atomicity sources sp1 sp2 sp3 sp4a sp4b sp5a sp5b sp6a sp6b | LC_ALL=C sort >"$tmp_dir/expected-directories"
  find "$root" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r directory; do basename "$directory"; done | LC_ALL=C sort >"$tmp_dir/actual-directories"
  cmp -s "$tmp_dir/expected-directories" "$tmp_dir/actual-directories" || { printf 'phase0 directory membership drift\n' >&2; exit 1; }
  if [[ -f "$root/conclusions.json" ]]; then
    { printf '%s\n' README.md environment.json manifest.sha256 privacy-audit.json run-all.json conclusions.json; printf 'SP-%s-CONCLUSION.md\n' 1 2 3 4A 4B 5A 5B 6A 6B; } | LC_ALL=C sort >"$tmp_dir/expected-root-files"
  else
    printf '%s\n' README.md environment.json manifest.sha256 privacy-audit.json run-all.json | LC_ALL=C sort >"$tmp_dir/expected-root-files"
  fi
  find "$root" -mindepth 1 -maxdepth 1 -type f -print | while IFS= read -r file; do basename "$file"; done | LC_ALL=C sort >"$tmp_dir/actual-root-files"
  cmp -s "$tmp_dir/expected-root-files" "$tmp_dir/actual-root-files" || { printf 'phase0 root file membership drift\n' >&2; exit 1; }
  (cd "$root" && shasum -a 256 -c manifest.sha256 >/dev/null)
  manifest_names="$tmp_dir/root-manifest-names"
  cut -d ' ' -f 3- "$root/manifest.sha256" | LC_ALL=C sort >"$manifest_names"
  comm -23 "$tmp_dir/expected-root-files" <(printf 'manifest.sha256\n' | LC_ALL=C sort) >"$tmp_dir/expected-manifest-names"
  cmp -s "$tmp_dir/expected-manifest-names" "$manifest_names" || { printf 'phase0 root manifest membership drift\n' >&2; exit 1; }
  for child in shared-atomicity sp1 sp2 sp3 sp4a sp4b sp5a sp5b sp6a sp6b fixtures/synthetic; do
    [[ -f "$root/$child/manifest.sha256" ]] || { printf 'missing child manifest: %s\n' "$child" >&2; exit 1; }
    (cd "$root/$child" && shasum -a 256 -c manifest.sha256 >/dev/null)
  done
  bash "$0" "$root/sources" >/dev/null
  printf 'MANIFEST_VERIFICATION=PASS hierarchy=phase0 root=%s\n' "$root"
  exit 0
fi

(cd "$root" && shasum -a 256 -c manifest.sha256 >/dev/null)
(cd "$root" && find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done) >"$tmp_dir/actual-manifest.sha256"
cmp -s "$root/manifest.sha256" "$tmp_dir/actual-manifest.sha256" || { printf 'manifest membership or hash drift\n' >&2; exit 1; }
[[ "$(find "$root" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d ' ')" == "2" && -d "$root/repos" && -d "$root/references" ]] || {
  printf 'unexpected source root directory membership\n' >&2; exit 1;
}
[[ "$(find "$root" -mindepth 1 -maxdepth 1 -type f ! -name manifest.sha256 -print | wc -l | tr -d ' ')" == "0" ]] || {
  printf 'unexpected source root file\n' >&2; exit 1;
}

verified=0
while IFS='|' read -r name url commit tree license_path license_blob required_paths required_blobs; do
  [[ -n "$name" && "${name:0:1}" != "#" ]] || continue
  provenance="$root/repos/$name/provenance.json"
  [[ -f "$provenance" ]] || { printf 'missing provenance: %s\n' "$name" >&2; exit 1; }
  jq -e --arg name "$name" --arg url "$url" --arg ref "$commit" --arg tree "$tree" --arg lp "$license_path" --arg lb "$license_blob" '
    keys == ["files","license","name","retrieved_at","tree","upstream_ref","url"] and
    .name == $name and .url == $url and .upstream_ref == $ref and .tree == $tree and
    (.upstream_ref | test("^[0-9a-f]{40}$")) and (.tree | test("^[0-9a-f]{40}$")) and
    (.retrieved_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and
    .license.path == $lp and .license.git_blob == $lb and
    (.license | keys == ["copied_path","git_blob","path","sha256"]) and
    ([.files[].path] | length == (unique | length)) and
    all(.files[]; (keys == ["copied_path","git_blob","path","sha256"]) and (.git_blob | test("^[0-9a-f]{40}$")) and (.sha256 | test("^[0-9a-f]{64}$")))
  ' "$provenance" >/dev/null || { printf 'malformed or drifted provenance metadata: %s\n' "$name" >&2; exit 1; }
  { jq -r '.files[].copied_path, .license.copied_path' "$provenance"; printf 'provenance.json\n'; } | LC_ALL=C sort >"$tmp_dir/$name-expected-files"
  (cd "$root/repos/$name" && find . -type f -print | cut -c 3- | LC_ALL=C sort) >"$tmp_dir/$name-actual-files"
  cmp -s "$tmp_dir/$name-expected-files" "$tmp_dir/$name-actual-files" || { printf 'unexpected copied source membership: %s\n' "$name" >&2; exit 1; }

  while IFS=$'\t' read -r path copied blob sha256; do
    file="$root/repos/$name/$copied"
    [[ -f "$file" ]] || { printf 'missing copied file: %s:%s\n' "$name" "$path" >&2; exit 1; }
    [[ "$(shasum -a 256 "$file" | cut -d ' ' -f 1)" == "$sha256" ]] || { printf 'sha256 drift: %s:%s\n' "$name" "$path" >&2; exit 1; }
    [[ "$(GIT_MASTER=1 git hash-object "$file")" == "$blob" ]] || { printf 'git blob drift: %s:%s\n' "$name" "$path" >&2; exit 1; }
    expected_blob="$(awk -F $'\t' -v name="$name" -v path="$path" '$1 == name && $2 == path { print $3 }' "$file_ledger")"
    [[ "$expected_blob" == "$blob" ]] || { printf 'immutable blob ledger drift: %s:%s\n' "$name" "$path" >&2; exit 1; }
  done < <(jq -r '.files[] | [.path,.copied_path,.git_blob,.sha256] | @tsv' "$provenance")

  license_file="$root/repos/$name/$(jq -r '.license.copied_path' "$provenance")"
  [[ "$(GIT_MASTER=1 git hash-object "$license_file")" == "$license_blob" ]] || { printf 'license blob drift: %s\n' "$name" >&2; exit 1; }
  [[ "$(shasum -a 256 "$license_file" | cut -d ' ' -f 1)" == "$(jq -r '.license.sha256' "$provenance")" ]] || { printf 'license sha256 drift: %s\n' "$name" >&2; exit 1; }

  IFS=';' read -r -a paths <<<"$required_paths"
  for requested in "${paths[@]}"; do
    [[ -n "$requested" ]] || continue
    if [[ "$requested" == */ ]]; then
      jq -e --arg prefix "$requested" 'any(.files[].path; startswith($prefix))' "$provenance" >/dev/null
    else
      jq -e --arg path "$requested" 'any(.files[].path; . == $path)' "$provenance" >/dev/null
    fi
  done
  if [[ -n "$required_blobs" ]]; then
    IFS=';' read -r -a checks <<<"$required_blobs"
    for check in "${checks[@]}"; do
      path="${check%%=*}"; expected="${check#*=}"
      jq -e --arg path "$path" --arg blob "$expected" 'any(.files[]; .path == $path and .git_blob == $blob)' "$provenance" >/dev/null
    done
  fi
  verified=$((verified + 1))
done <"$ledger"
[[ "$verified" -eq 9 ]] || { printf 'ledger row count drift: %s\n' "$verified" >&2; exit 1; }
awk -F '|' '$1 !~ /^#/ && $1 != "" { print $1 }' "$ledger" | LC_ALL=C sort >"$tmp_dir/expected-repos"
find "$root/repos" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r directory; do basename "$directory"; done | LC_ALL=C sort >"$tmp_dir/actual-repos"
cmp -s "$tmp_dir/expected-repos" "$tmp_dir/actual-repos" || { printf 'repository set drift\n' >&2; exit 1; }
actual_file_count="$(find "$root/repos" -name provenance.json -exec jq '.files | length' {} + | awk '{ total += $1 } END { print total + 0 }')"
expected_file_count="$(wc -l <"$file_ledger" | tr -d ' ')"
[[ "$actual_file_count" == "$expected_file_count" ]] || { printf 'immutable source file count drift\n' >&2; exit 1; }

expected_urls="$tmp_dir/reference-urls"
cat >"$expected_urls" <<'URLS'
https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()
https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication
https://developer.apple.com/library/archive/technotes/tn2150/_index.html
https://developer.apple.com/documentation/cryptokit/aes/gcm
https://developer.apple.com/documentation/cryptokit/hkdf
https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly.md
https://www.rfc-editor.org/rfc/rfc9106.html
https://csrc.nist.gov/pubs/sp/800/38/d/final
URLS
: >"$tmp_dir/actual-urls"
: >"$tmp_dir/reference-expected-files"
for metadata in "$root"/references/reference-*.json; do
  [[ -f "$metadata" ]] || { printf 'reference metadata missing\n' >&2; exit 1; }
  jq -r '.url' "$metadata" >>"$tmp_dir/actual-urls"
  basename "$metadata" >>"$tmp_dir/reference-expected-files"
  status="$(jq -r '.status' "$metadata")"
  if [[ "$status" == "CAPTURED" ]]; then
    jq -e '.http_status == 200 and (.response_sha256 | test("^[0-9a-f]{64}$"))' "$metadata" >/dev/null
    body="${metadata%.json}.body"
    basename "$body" >>"$tmp_dir/reference-expected-files"
    [[ -f "$body" && "$(shasum -a 256 "$body" | cut -d ' ' -f 1)" == "$(jq -r '.response_sha256' "$metadata")" ]] || { printf 'reference response drift: %s\n' "$metadata" >&2; exit 1; }
  elif [[ "$status" == "BLOCKED" ]]; then
    jq -e '.blocker.blocked_by != "" and (.blocker.detect_command | length > 0) and .blocker.prerequisite != "" and .blocker.unblock_action != ""' "$metadata" >/dev/null
    [[ ! -e "${metadata%.json}.body" ]] || { printf 'blocked reference retained unverified body\n' >&2; exit 1; }
  else
    printf 'invalid reference status: %s\n' "$status" >&2; exit 1
  fi
done
cmp -s "$expected_urls" "$tmp_dir/actual-urls" || { printf 'mutable primary reference set drift\n' >&2; exit 1; }

sdk="$root/references/sdk/provenance.json"
jq -e '(.headers | length) == 5 and all(.headers[]; has("path") and ((has("sha256") and has("copied_path")) or (.status == "BLOCKED" and .blocker != "")))' "$sdk" >/dev/null
while IFS=$'\t' read -r copied sha256; do
  [[ -n "$copied" ]] || continue
  file="$root/references/sdk/$copied"
  [[ -f "$file" && "$(shasum -a 256 "$file" | cut -d ' ' -f 1)" == "$sha256" ]] || { printf 'SDK header drift: %s\n' "$copied" >&2; exit 1; }
done < <(jq -r '.headers[] | select(has("copied_path")) | [.copied_path,.sha256] | @tsv' "$sdk")
printf 'sdk/provenance.json\n' >>"$tmp_dir/reference-expected-files"
jq -r '.headers[] | select(has("copied_path")) | "sdk/" + .copied_path' "$sdk" >>"$tmp_dir/reference-expected-files"
LC_ALL=C sort -o "$tmp_dir/reference-expected-files" "$tmp_dir/reference-expected-files"
(cd "$root/references" && find . -type f -print | cut -c 3- | LC_ALL=C sort) >"$tmp_dir/reference-actual-files"
cmp -s "$tmp_dir/reference-expected-files" "$tmp_dir/reference-actual-files" || { printf 'unexpected reference snapshot membership\n' >&2; exit 1; }

printf 'MANIFEST_VERIFICATION=PASS repos=%d root=%s\n' "$verified" "$root"
