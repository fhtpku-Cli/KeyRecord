#!/usr/bin/env bash
set -euo pipefail
output="${1:-evidence/phase0/sp6b/d12}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
review_contract="$script_dir/sp6b-nvd-review.json"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-d12.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP
mkdir -p "$tmp_dir/result/raw"
retrieved_at="${KEYRECORD_SP6B_GENERATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
zero="$(printf '[]')"

sanitize_response_headers() {
  local path="$1" sanitized="$1.sanitized" line
  : >"$sanitized"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    while [[ "$line" == *[[:space:]] ]]; do line="${line%?}"; done
    [[ -n "$line" ]] || continue
    case "$line" in
      [Ss][Ee][Tt]-[Cc][Oo][Oo][Kk][Ii][Ee]:*|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]:*|[Pp][Rr][Oo][Xx][Yy]-[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]:*|[Xx]-[Aa][Pp][Ii]-[Kk][Ee][Yy]:*|[Aa][Pp][Ii]-[Kk][Ee][Yy]:*|[Aa][Uu][Tt][Hh][Ee][Nn][Tt][Ii][Cc][Aa][Tt][Ii][Oo][Nn]-[Ii][Nn][Ff][Oo]:*) ;;
      *) printf '%s\n' "$line" >>"$sanitized" ;;
    esac
  done <"$path"
  mv "$sanitized" "$path"
}

page_json() {
  local url="$1" body="$2" status="$3" headers="$4" raw="$5" next="$6"
  local headers_hash raw_hash
  headers_hash="$(shasum -a 256 "$tmp_dir/result/$headers" | cut -d' ' -f1)"
  raw_hash="$(shasum -a 256 "$tmp_dir/result/$raw" | cut -d' ' -f1)"
  jq -cn --arg url "$url" --arg body "$body" --argjson status "$status" --arg retrievedAt "$retrieved_at" \
    --arg headersSha256 "$headers_hash" --arg rawBodySha256 "$raw_hash" --arg headersPath "$headers" \
    --arg rawBodyPath "$raw" --arg next "$next" \
    '{url:$url,requestBody:(if $body=="" then null else $body end),status:$status,retrievedAt:$retrievedAt,headersSha256:$headersSha256,rawBodySha256:$rawBodySha256,headersPath:$headersPath,rawBodyPath:$rawBodyPath,next:(if $next=="" then null else $next end)}'
}

github_pages() {
  local id="$1" repo="$2" page=0 pages="$zero" url
  url="https://api.github.com/repos/$repo/security-advisories?per_page=100"
  while [[ -n "$url" ]]; do
    local headers="raw/github-$id-$page.headers" raw="raw/github-$id-$page.json" status next=""
    status="$(curl --silent --show-error --location --dump-header "$tmp_dir/result/$headers" --output "$tmp_dir/result/$raw" --write-out '%{http_code}' -H 'Accept: application/vnd.github+json' "$url")"
    sanitize_response_headers "$tmp_dir/result/$headers"
    [[ "$status" == 200 ]]
    jq -e 'type == "array"' "$tmp_dir/result/$raw" >/dev/null
    while IFS= read -r line; do
      if [[ "$line" =~ \<([^\>]*)\>\;[[:space:]]*rel=\"next\" ]]; then next="${BASH_REMATCH[1]}"; fi
    done <"$tmp_dir/result/$headers"
    pages="$(jq -cn --argjson pages "$pages" --argjson page "$(page_json "$url" "" "$status" "$headers" "$raw" "$next")" '$pages + [$page]')"
    url="$next"; page=$((page + 1)); [[ "$page" -le 100 ]]
  done
  printf '%s' "$pages"
}

osv_pages() {
  local id="$1" commit="$2" token="" page=0 pages="$zero"
  while true; do
    local body headers="raw/osv-$id-$page.headers" raw="raw/osv-$id-$page.json" status next
    if [[ -z "$token" ]]; then body="{\"commit\":\"$commit\"}"; else body="{\"commit\":\"$commit\",\"page_token\":\"$token\"}"; fi
    status="$(curl --silent --show-error --dump-header "$tmp_dir/result/$headers" --output "$tmp_dir/result/$raw" --write-out '%{http_code}' -H 'Content-Type: application/json' --data-binary "$body" https://api.osv.dev/v1/query)"
    sanitize_response_headers "$tmp_dir/result/$headers"
    [[ "$status" == 200 ]]
    jq -e 'type == "object"' "$tmp_dir/result/$raw" >/dev/null
    next="$(jq -r '.next_page_token // ""' "$tmp_dir/result/$raw")"
    request="$(page_json "https://api.osv.dev/v1/query" "$body" "$status" "$headers" "$raw" "")"
    pages="$(jq -cn --argjson pages "$pages" --argjson request "$request" --arg next "$next" '$pages + [{request:$request,responseNextPageToken:(if $next=="" then null else $next end)}]')"
    [[ -z "$next" ]] && break
    [[ "$next" != "$token" ]]; token="$next"; page=$((page + 1)); [[ "$page" -le 100 ]]
  done
  printf '%s' "$pages"
}

phc_github="$(github_pages phc P-H-C/phc-winner-argon2)"
swift_github="$(github_pages swift MarlonJD/argon2id-swift-native)"
phc_osv="$(osv_pages phc f57e61e19229e23c4445b85494dbf7c07de721cb)"
swift_osv="$(osv_pages swift 14d47de1914ac63b368ddb2cfe0f47ffe25f04cf)"

nvd_pages="$zero"; start=0; expected_total=""; seen=0; page=0; seen_ids="$zero"
while true; do
  base='https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=argon2&resultsPerPage=2000'
  if [[ "$start" -eq 0 ]]; then url="$base"; else url="$base&startIndex=$start"; fi
  headers="raw/nvd-$page.headers"; raw="raw/nvd-$page.json"
  status="$(curl --silent --show-error --location --dump-header "$tmp_dir/result/$headers" --output "$tmp_dir/result/$raw" --write-out '%{http_code}' "$url")"
  sanitize_response_headers "$tmp_dir/result/$headers"
  [[ "$status" == 200 ]]
  total="$(jq -r '.totalResults' "$tmp_dir/result/$raw")"; results="$(jq -r '.resultsPerPage' "$tmp_dir/result/$raw")"
  response_start="$(jq -r '.startIndex' "$tmp_dir/result/$raw")"; [[ "$response_start" == "$start" ]]
  [[ -z "$expected_total" || "$total" == "$expected_total" ]]; expected_total="$total"
  vulnerabilities="$zero"; count="$(jq '.vulnerabilities|length' "$tmp_dir/result/$raw")"
  for index in $(seq 0 $((count - 1))); do
    cve="$(jq -c ".vulnerabilities[$index].cve" "$tmp_dir/result/$raw")"; id="$(jq -r .id <<<"$cve")"
    description="$(jq -r 'first(.descriptions[]|select(.lang=="en")|.value)' <<<"$cve")"
    configurations="$(jq -cS '(.configurations // [])' <<<"$cve")"; references="$(jq -cS '(.references // [])' <<<"$cve")"
    description_hash="$(printf %s "$description" | shasum -a 256 | cut -d' ' -f1)"
    configuration_hash="$(printf %s "$configurations" | shasum -a 256 | cut -d' ' -f1)"
    references_hash="$(printf %s "$references" | shasum -a 256 | cut -d' ' -f1)"
    disposition="$(jq -ce --arg id "$id" '.dispositions[]|select(.cveID==$id)' "$review_contract")"
    jq -e --arg description "$description_hash" --arg configuration "$configuration_hash" --arg references "$references_hash" \
      '.descriptionSha256==$description and .configurationSha256==$configuration and .referencesSha256==$references' <<<"$disposition" >/dev/null
    vulnerabilities="$(jq -cn --argjson values "$vulnerabilities" --argjson value "$disposition" '$values+[$value]')"
    seen_ids="$(jq -cn --argjson values "$seen_ids" --arg id "$id" '$values+[$id]')"
  done
  seen=$((seen + count))
  request="$(page_json "$url" "" "$status" "$headers" "$raw" "")"
  nvd_pages="$(jq -cn --argjson pages "$nvd_pages" --argjson request "$request" --argjson start "$start" --argjson results "$results" --argjson total "$total" --argjson vulnerabilities "$vulnerabilities" '$pages + [{request:$request,startIndex:$start,resultsPerPage:$results,totalResults:$total,vulnerabilities:$vulnerabilities}]')"
  [[ "$seen" -ge "$total" ]] && break
  start=$((start + results)); page=$((page + 1)); [[ "$page" -le 100 ]]
done
[[ "$seen" == "$expected_total" ]]
review_revision="$(jq -r .auditRevision "$review_contract")"
jq -e --argjson seen "$seen_ids" '([.dispositions[].cveID]|sort)==($seen|sort) and ([.dispositions[].cveID]|unique|length)==(.dispositions|length)' "$review_contract" >/dev/null

generated_at="$retrieved_at"
jq -n --arg generatedAt "$generated_at" --argjson phcGithub "$phc_github" --argjson phcOsv "$phc_osv" \
  --argjson swiftGithub "$swift_github" --argjson swiftOsv "$swift_osv" --argjson nvd "$nvd_pages" \
  --arg reviewRevision "$review_revision" \
  '{schemaVersion:2,generatedAt:$generatedAt,candidates:[{id:"phc",ownerRepo:"P-H-C/phc-winner-argon2",commit:"f57e61e19229e23c4445b85494dbf7c07de721cb",github:$phcGithub,osv:$phcOsv},{id:"swift",ownerRepo:"MarlonJD/argon2id-swift-native",commit:"14d47de1914ac63b368ddb2cfe0f47ffe25f04cf",github:$swiftGithub,osv:$swiftOsv}],nvd:{auditRevision:$reviewRevision,pages:$nvd}}' >"$tmp_dir/result/snapshot.json"
mkdir -p "$(dirname "$output")"; rm -rf "$output"; mv "$tmp_dir/result" "$output"
printf 'D12_CAPTURE=PASS github_pages=%s osv_pages=%s nvd_pages=%s nvd_hits=%s generated_at=%s\n' \
  "$(jq '[.candidates[].github[]]|length' "$output/snapshot.json")" "$(jq '[.candidates[].osv[]]|length' "$output/snapshot.json")" \
  "$(jq '.nvd.pages|length' "$output/snapshot.json")" "$seen" "$generated_at"
