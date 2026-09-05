#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -m)" == "arm64" ]] || { printf 'ARM benchmark requires arm64 host.\n' >&2; exit 69; }
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-argon-bench.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP
output="${1:-evidence/phase0/sp6b/arm-benchmark.json}"
commit="f57e61e19229e23c4445b85494dbf7c07de721cb"
git clone --quiet --filter=blob:none --no-checkout https://github.com/P-H-C/phc-winner-argon2.git "$tmp_dir/phc"
git -C "$tmp_dir/phc" fetch --quiet --depth 1 origin "$commit"
git -C "$tmp_dir/phc" checkout --quiet --detach "$commit"
[[ "$(git -C "$tmp_dir/phc" rev-parse HEAD)" == "$commit" && "$(git -C "$tmp_dir/phc" rev-parse 'HEAD^{tree}')" == "ac3dc753ff75ce5a0f243cba1d94582bafe09409" ]]
clang -arch arm64 -mmacosx-version-min=14.0 -std=c89 -O3 -fno-strict-aliasing -I"$tmp_dir/phc/include" -I"$tmp_dir/phc/src" \
  "$tmp_dir/phc/src/argon2.c" "$tmp_dir/phc/src/core.c" "$tmp_dir/phc/src/blake2/blake2b.c" "$tmp_dir/phc/src/thread.c" \
  "$tmp_dir/phc/src/encoding.c" "$tmp_dir/phc/src/ref.c" "$(cd "$(dirname "$0")" && pwd)/argon-bench.c" -o "$tmp_dir/bench"

memory=524288; iterations=5; parallelism=4; sample_count=7
samples='[]'
for _ in $(seq 1 "$sample_count"); do
  value="$("$tmp_dir/bench" "$memory" "$iterations" "$parallelism")"
  samples="$(jq -c --argjson value "$value" '. + [$value]' <<<"$samples")"
done
median="$(jq -r 'sort | .[length/2|floor]' <<<"$samples")"
p95="$(jq -r 'sort | .[((length * 95 + 99) / 100 | floor) - 1]' <<<"$samples")"
within="$(jq -n --argjson median "$median" '$median >= 300 and $median <= 500')"
if [[ "$within" != true ]]; then
  printf 'ARM benchmark median outside 300-500 ms: %s\n' "$median" >&2
  exit 1
fi
mkdir -p "$(dirname "$output")"
jq -n --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg os "$(sw_vers -productVersion)" --arg build "$(sw_vers -buildVersion)" \
  --arg swift "$(xcrun swift --version | tr '\n' ' ')" --argjson samples "$samples" --argjson median "$median" --argjson p95 "$p95" \
  --argjson memory "$memory" --argjson iterations "$iterations" --argjson parallelism "$parallelism" \
  --argjson within "$within" \
  '{schemaVersion:1,generatedAt:$generatedAt,recommendedCandidate:"phc",commit:"f57e61e19229e23c4445b85494dbf7c07de721cb",host:{architecture:"arm64",macOS:$os,build:$build,swift:$swift},samplesMilliseconds:$samples,medianMilliseconds:$median,p95Milliseconds:$p95,memoryKiB:$memory,iterations:$iterations,parallelism:$parallelism,saltLength:16,sampleCount:($samples|length),targetMilliseconds:{minimum:300,maximum:500},withinTarget:$within}' >"$output"
printf 'ARGON_ARM_TIMING=PASS samples=%s median_ms=%s p95_ms=%s memory_kib=%s iterations=%s parallelism=%s\n' "$sample_count" "$median" "$p95" "$memory" "$iterations" "$parallelism"
