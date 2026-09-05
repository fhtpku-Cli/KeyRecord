#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-argon.XXXXXX")"
cleanup() { status=$?; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP

repository="https://github.com/P-H-C/phc-winner-argon2.git"
commit="f57e61e19229e23c4445b85494dbf7c07de721cb"
tree="ac3dc753ff75ce5a0f243cba1d94582bafe09409"
license_blob="a16d6d2ffee94866a0fb5ce3ab08a5b9c49967af"
swift_repository="https://github.com/MarlonJD/argon2id-swift-native.git"
swift_commit="14d47de1914ac63b368ddb2cfe0f47ffe25f04cf"
swift_tree="4bb860f4c47b4b327ea207da3fe7a007a05c7b81"
output_dir="${KEYRECORD_ARGON_OUTPUT_DIR:-evidence/phase0/sp6b/build}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
contract="$script_dir/sp6b-source-contract.json"
generated_at="${KEYRECORD_SP6B_GENERATED_AT:?missing KEYRECORD_SP6B_GENERATED_AT}"
flags=("-mmacosx-version-min=14.0" "-std=c89" "-O3" "-Wall" "-Wextra" "-Werror" "-fno-strict-aliasing")
compiler_identity="$(xcrun clang --version)"
[[ "$(printf %s "$compiler_identity"|shasum -a 256|cut -d' ' -f1)" == "$(jq -r .compilerIdentitySha256 "$contract")" ]]

clone_exact() {
  local url="$1" revision="$2" expected_tree="$3" destination="$4"
  git clone --quiet --filter=blob:none --no-checkout "$url" "$destination"
  git -C "$destination" fetch --quiet --depth 1 origin "$revision"
  git -C "$destination" checkout --quiet --detach "$revision"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
  [[ "$(git -C "$destination" rev-parse 'HEAD^{tree}')" == "$expected_tree" ]]
}

clone_exact "$repository" "$commit" "$tree" "$tmp_dir/phc"
[[ "$(git -C "$tmp_dir/phc" rev-parse HEAD:LICENSE)" == "$license_blob" ]]
clone_exact "$swift_repository" "$swift_commit" "$swift_tree" "$tmp_dir/swift"
[[ "$(git -C "$tmp_dir/swift" rev-parse HEAD:LICENSE)" == "4184b3c65a47bddfbd807eed1a4939a69d8d7535" ]]

sources=(src/argon2.c src/core.c src/blake2/blake2b.c src/thread.c src/encoding.c src/ref.c)
slices='[]'
for arch in x86_64 arm64; do
  mkdir -p "$tmp_dir/$arch"
  objects=()
  for source in "${sources[@]}"; do
    object="$tmp_dir/$arch/$(basename "${source%.c}").o"
    clang -arch "$arch" "${flags[@]}" \
      -I"$tmp_dir/phc/include" -I"$tmp_dir/phc/src" -c "$tmp_dir/phc/$source" -o "$object"
    objects+=("$object")
  done
  ZERO_AR_DATE=1 ar -rcs "$tmp_dir/libargon2-$arch.a" "${objects[@]}"
done

swift build --package-path "$tmp_dir/swift" --scratch-path "$tmp_dir/swift-arm" --triple arm64-apple-macosx14.0 >/dev/null
swift build --package-path "$tmp_dir/swift" --scratch-path "$tmp_dir/swift-intel" --triple x86_64-apple-macosx14.0 >/dev/null
swift test --package-path "$tmp_dir/swift" --scratch-path "$tmp_dir/swift-test" >/dev/null

mkdir -p "$output_dir"
lipo -create "$tmp_dir/libargon2-x86_64.a" "$tmp_dir/libargon2-arm64.a" -output "$output_dir/argon2-universal.a"
archs="$(lipo -archs "$output_dir/argon2-universal.a")"
[[ "$archs" == "x86_64 arm64" || "$archs" == "arm64 x86_64" ]]
clang -arch "$(uname -m)" -mmacosx-version-min=14.0 -O2 -I"$tmp_dir/phc/include" \
  "$script_dir/argon-vector.c" "$output_dir/argon2-universal.a" -o "$tmp_dir/argon-vector"
set +e; phc_output="$("$tmp_dir/argon-vector")"; phc_status=$?; set -e
[[ "$phc_status" == 0 ]]; printf '%s\n' "$phc_output" >"$output_dir/phc-vector.txt"
xcrun swiftc "$tmp_dir/swift/Sources/Argon2idSwiftNative/Argon2id.swift" "$script_dir/argon-swift-vector.swift" -o "$tmp_dir/swift-vector"
set +e; swift_tag="$("$tmp_dir/swift-vector")"; swift_status=$?; set -e
[[ "$swift_status" == 0 ]]; printf '%s\n' "$swift_tag" >"$output_dir/swift-vector.txt"
expected_tag="0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
phc_tag="${phc_output##*tag=}"; [[ "$phc_tag" == "$expected_tag" && "$swift_tag" == "$expected_tag" ]]

for arch in x86_64 arm64; do
  thin="$tmp_dir/thin-$arch.a"; members='[]'; extract="$tmp_dir/extract-$arch"; mkdir -p "$extract"
  lipo -thin "$arch" "$output_dir/argon2-universal.a" -output "$thin"
  while IFS= read -r member; do
    [[ "$member" == *.o ]] || continue
    (cd "$extract" && ar -x "$thin" "$member")
    object="$extract/$member"; object_arch="$(lipo -archs "$object")"; [[ "$object_arch" == "$arch" ]]
    stem="${member%.o}"; source_path=""
    for candidate_source in "${sources[@]}"; do [[ "$(basename "${candidate_source%.c}")" == "$stem" ]] && source_path="$candidate_source"; done
    [[ -n "$source_path" ]]
    source_contract="$(jq -ce --arg path "$source_path" '.candidates[]|select(.id=="phc")|.includedFiles[]|select(.path==$path)' "$contract")"
    member_receipt="$(jq -cn --arg member "$member" --arg arch "$object_arch" --arg path "$source_path" \
      --arg blob "$(jq -r .blob <<<"$source_contract")" --arg sourceSha "$(jq -r .sha256 <<<"$source_contract")" \
      --arg objectSha "$(shasum -a 256 "$object" | cut -d' ' -f1)" \
      '{member:$member,machOArchitecture:$arch,sourcePath:$path,sourceBlob:$blob,sourceSha256:$sourceSha,objectSha256:$objectSha}')"
    members="$(jq -cn --argjson values "$members" --argjson value "$member_receipt" '$values+[$value]')"
  done < <(ar -t "$thin")
  slice="$(jq -cn --arg arch "$arch" --arg sha "$(shasum -a 256 "$thin" | cut -d' ' -f1)" --argjson members "$members" \
    '{architecture:$arch,sliceSha256:$sha,members:$members}')"
  slices="$(jq -cn --argjson values "$slices" --argjson value "$slice" '$values+[$value]')"
done
archive_hash="$(shasum -a 256 "$output_dir/argon2-universal.a" | cut -d' ' -f1)"
jq -n --arg generatedAt "$generated_at" --arg commit "$commit" --arg tree "$tree" --arg archs "$archs" --arg sha256 "$archive_hash" \
  --arg compiler "$compiler_identity" --arg swiftCommit "$swift_commit" --arg swiftTree "$swift_tree" --arg expected "$expected_tag" \
  --arg phcObserved "$phc_tag" --arg swiftObserved "$swift_tag" --arg phcExecutable "$(shasum -a 256 "$tmp_dir/argon-vector"|cut -d' ' -f1)" \
  --arg swiftExecutable "$(shasum -a 256 "$tmp_dir/swift-vector"|cut -d' ' -f1)" \
  --arg phcHarness "$(shasum -a 256 "$script_dir/argon-vector.c"|cut -d' ' -f1)" \
  --arg swiftHarness "$(shasum -a 256 "$script_dir/argon-swift-vector.swift"|cut -d' ' -f1)" \
  --arg swiftSource "$(shasum -a 256 "$tmp_dir/swift/Sources/Argon2idSwiftNative/Argon2id.swift"|cut -d' ' -f1)" \
  --argjson phcStatus "$phc_status" --argjson swiftStatus "$swift_status" --argjson slices "$slices" \
  '{schemaVersion:2,generatedAt:$generatedAt,recommendedCandidate:"phc",commit:$commit,tree:$tree,minimumMacOS:"14.0",architectures:($archs|split(" ")|sort),archiveSha256:$sha256,compilerIdentity:$compiler,compilerFlags:["-mmacosx-version-min=14.0","-std=c89","-O3","-Wall","-Wextra","-Werror","-fno-strict-aliasing"],slices:$slices,swiftCandidate:{commit:$swiftCommit,tree:$swiftTree,arm64MacOS14:true,x86_64MacOS14:true},vectors:[{candidateID:"phc",commit:$commit,tree:$tree,command:["clang","argon-vector.c","argon2-universal.a"],inputs:{passwordByte:"01",passwordLength:32,saltByte:"02",saltLength:16,secretByte:"03",secretLength:8,associatedDataByte:"04",associatedDataLength:12,memoryKiB:32,iterations:3,parallelism:4,outputLength:32},expectedTag:$expected,observedTag:$phcObserved,harnessSourceSha256:$phcHarness,candidateSourceSha256:null,executableSha256:$phcExecutable,exitStatus:$phcStatus},{candidateID:"swift",commit:$swiftCommit,tree:$swiftTree,command:["xcrun","swiftc","Argon2id.swift","argon-swift-vector.swift"],inputs:{passwordByte:"01",passwordLength:32,saltByte:"02",saltLength:16,secretByte:"03",secretLength:8,associatedDataByte:"04",associatedDataLength:12,memoryKiB:32,iterations:3,parallelism:4,outputLength:32},expectedTag:$expected,observedTag:$swiftObserved,harnessSourceSha256:$swiftHarness,candidateSourceSha256:$swiftSource,executableSha256:$swiftExecutable,exitStatus:$swiftStatus}]}' >"$output_dir/build.json"
jq -e --slurpfile contract "$contract" '
  .archiveSha256==$contract[0].deterministicBuild.archiveSha256 and
  all(.slices[]; . as $slice | ($contract[0].deterministicBuild.slices[]|select(.architecture==$slice.architecture)) as $expected |
    $slice.sliceSha256==$expected.sliceSha256 and all($slice.members[]; .objectSha256==$expected.objects[.member]))
' "$output_dir/build.json" >/dev/null
printf 'ARGON_UNIVERSAL_BUILD=PASS archs=%s sha256=%s output=%s\n' "$archs" "$archive_hash" "$output_dir/argon2-universal.a"
