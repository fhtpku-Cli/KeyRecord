#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { printf 'Usage: %s OUTPUT\n' "$0" >&2; exit 64; }
output="$1"; script_dir="$(cd "$(dirname "$0")" && pwd)"; contract="$script_dir/sp6b-source-contract.json"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-argon-source-audit.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP
generated_at="${KEYRECORD_SP6B_GENERATED_AT:?missing KEYRECORD_SP6B_GENERATED_AT}"
receipts='[]'
for id in phc swift; do
  expected="$(jq -ce --arg id "$id" '.candidates[]|select(.id==$id)' "$contract")"
  url="$(jq -r .canonicalURL <<<"$expected")"; commit="$(jq -r .commit <<<"$expected")"; tree="$(jq -r .tree <<<"$expected")"
  repo="$tmp_dir/$id"; git clone --quiet --filter=blob:none --no-checkout "$url" "$repo"
  git -C "$repo" fetch --quiet --depth 1 origin "$commit"; git -C "$repo" checkout --quiet --detach "$commit"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$commit" && "$(git -C "$repo" rev-parse 'HEAD^{tree}')" == "$tree" ]]
  [[ "$(git -C "$repo" rev-parse HEAD:LICENSE)" == "$(jq -r .licenseBlob <<<"$expected")" ]]
  [[ "$(git -C "$repo" rev-parse HEAD:Package.swift)" == "$(jq -r .packageBlob <<<"$expected")" ]]
  listing_hash="$(git -C "$repo" ls-tree -r --full-tree HEAD | shasum -a 256 | cut -d' ' -f1)"
  [[ "$listing_hash" == "$(jq -r .treeListingSha256 <<<"$expected")" ]]
  files='[]'; total=0
  while IFS= read -r file; do
    path="$(jq -r .path <<<"$file")"; blob="$(git -C "$repo" rev-parse "HEAD:$path")"
    sha256="$(shasum -a 256 "$repo/$path" | cut -d' ' -f1)"; lines="$(wc -l <"$repo/$path" | tr -d ' ')"
    jq -e --arg blob "$blob" --arg sha256 "$sha256" --argjson lines "$lines" \
      '.blob==$blob and .sha256==$sha256 and .lineCount==$lines' <<<"$file" >/dev/null
    files="$(jq -cn --argjson values "$files" --argjson value "$file" '$values+[$value]')"; total=$((total + lines))
  done < <(jq -c '.includedFiles[]' <<<"$expected")
  [[ "$total" == "$(jq -r .sourceLOC <<<"$expected")" ]]
  receipt="$(jq -cn --argjson contract "$expected" --argjson files "$files" --arg listing "$listing_hash" --argjson total "$total" \
    '$contract + {includedFiles:$files,treeListingSha256:$listing,sourceLOC:$total}')"
  receipts="$(jq -cn --argjson values "$receipts" --argjson value "$receipt" '$values+[$value]')"
done
mkdir -p "$(dirname "$output")"
jq -n --arg generatedAt "$generated_at" --argjson candidates "$receipts" '{schemaVersion:1,generatedAt:$generatedAt,candidates:$candidates}' >"$output"
printf 'ARGON_SOURCE_AUDIT=PASS candidates=2 output=%s\n' "$output"
