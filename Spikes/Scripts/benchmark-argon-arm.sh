#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -m)" == "arm64" ]] || { printf 'ARM benchmark requires arm64 host.\n' >&2; exit 69; }
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-argon-bench.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP
output="${1:-evidence/phase0/sp6b/arm-benchmark.json}"
commit="f57e61e19229e23c4445b85494dbf7c07de721cb"
tree="ac3dc753ff75ce5a0f243cba1d94582bafe09409"
generated_at="${KEYRECORD_SP6B_GENERATED_AT:?missing KEYRECORD_SP6B_GENERATED_AT}"
environment_hash="${KEYRECORD_SP6B_ENVIRONMENT_SHA256:?missing KEYRECORD_SP6B_ENVIRONMENT_SHA256}"
archive_hash="${KEYRECORD_SP6B_ARCHIVE_SHA256:?missing KEYRECORD_SP6B_ARCHIVE_SHA256}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
compiler_identity="$(xcrun clang --version)"
[[ "$(printf %s "$compiler_identity"|shasum -a 256|cut -d' ' -f1)" == "$(jq -r .compilerIdentitySha256 "$script_dir/sp6b-source-contract.json")" ]]
git clone --quiet --filter=blob:none --no-checkout https://github.com/P-H-C/phc-winner-argon2.git "$tmp_dir/phc"
git -C "$tmp_dir/phc" fetch --quiet --depth 1 origin "$commit"
git -C "$tmp_dir/phc" checkout --quiet --detach "$commit"
[[ "$(git -C "$tmp_dir/phc" rev-parse HEAD)" == "$commit" && "$(git -C "$tmp_dir/phc" rev-parse 'HEAD^{tree}')" == "ac3dc753ff75ce5a0f243cba1d94582bafe09409" ]]
clang -arch arm64 -mmacosx-version-min=14.0 -std=c89 -O3 -fno-strict-aliasing -I"$tmp_dir/phc/include" -I"$tmp_dir/phc/src" \
  "$tmp_dir/phc/src/argon2.c" "$tmp_dir/phc/src/core.c" "$tmp_dir/phc/src/blake2/blake2b.c" "$tmp_dir/phc/src/thread.c" \
  "$tmp_dir/phc/src/encoding.c" "$tmp_dir/phc/src/ref.c" "$script_dir/argon-bench.c" -o "$tmp_dir/bench"

memory=524288; iterations=5; parallelism=4; sample_count=7
samples='[]'; receipts='[]'; previous_end=0
for index in $(seq 0 $((sample_count - 1))); do
  receipt="$("$tmp_dir/bench" "$memory" "$iterations" "$parallelism")"
  jq -e --argjson previous "$previous_end" --arg expected "$(jq -r .benchmarkExpectedTag "$script_dir/sp6b-source-contract.json")" \
    '.startNanoseconds>= $previous and .endNanoseconds>.startNanoseconds and .milliseconds>0 and .observedTag==$expected' <<<"$receipt" >/dev/null
  previous_end="$(jq -r .endNanoseconds <<<"$receipt")"; value="$(jq -r .milliseconds <<<"$receipt")"
  receipt="$(jq -cn --argjson receipt "$receipt" --argjson index "$index" '$receipt+{index:$index}')"
  receipts="$(jq -c --argjson value "$receipt" '. + [$value]' <<<"$receipts")"
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
jq -n --arg generatedAt "$generated_at" --arg os "$(sw_vers -productVersion)" --arg build "$(sw_vers -buildVersion)" \
  --arg swift "$(xcrun swift --version | tr '\n' ' ')" --argjson samples "$samples" --argjson median "$median" --argjson p95 "$p95" \
  --argjson receipts "$receipts" --arg tree "$tree" --arg archive "$archive_hash" --arg environment "$environment_hash" \
  --arg harness "$(shasum -a 256 "$script_dir/argon-bench.c"|cut -d' ' -f1)" --arg executable "$(shasum -a 256 "$tmp_dir/bench"|cut -d' ' -f1)" \
  --arg compiler "$compiler_identity" \
  --argjson memory "$memory" --argjson iterations "$iterations" --argjson parallelism "$parallelism" \
  --argjson within "$within" \
  '{schemaVersion:2,generatedAt:$generatedAt,recommendedCandidate:"phc",commit:"f57e61e19229e23c4445b85494dbf7c07de721cb",tree:$tree,archiveSha256:$archive,environmentSha256:$environment,harnessSourceSha256:$harness,executableSha256:$executable,compilerIdentity:$compiler,compilerFlags:["-arch","arm64","-mmacosx-version-min=14.0","-std=c89","-O3","-fno-strict-aliasing"],command:["argon-bench","524288","5","4"],host:{architecture:"arm64",macOS:$os,build:$build,swift:$swift},sampleReceipts:$receipts,samplesMilliseconds:$samples,medianMilliseconds:$median,p95Milliseconds:$p95,memoryKiB:$memory,iterations:$iterations,parallelism:$parallelism,saltLength:16,sampleCount:($samples|length),targetMilliseconds:{minimum:300,maximum:500},withinTarget:$within}' >"$output"
printf 'ARGON_ARM_TIMING=PASS samples=%s median_ms=%s p95_ms=%s memory_kib=%s iterations=%s parallelism=%s\n' "$sample_count" "$median" "$p95" "$memory" "$iterations" "$parallelism"
