#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
STAGING="${1:-/tmp/keyrecord-g0-attempt}"
DEST="$REPO_ROOT/evidence/phase0"
SP1_SRC="$STAGING/sp1"
ENV_SRC="$STAGING/environment.json"
BUILD_BIN="$REPO_ROOT/Spikes/.build/release/EvidenceValidator"

[[ -d "$SP1_SRC" ]] || { echo "missing sp1 evidence: $SP1_SRC" >&2; exit 1; }
[[ -f "$ENV_SRC" ]] || { echo "missing environment: $ENV_SRC" >&2; exit 1; }

expected="$(python3 -c "import json; print(json.load(open('$SP1_SRC/evidence.json'))['legs'][0]['environmentSha256'])")"
actual="$(python3 -c "import hashlib; print(hashlib.sha256(open('$ENV_SRC','rb').read()).hexdigest())")"
if [[ "$expected" != "$actual" ]]; then
  echo "environment hash mismatch expected=$expected actual=$actual" >&2
  echo "Re-run: bash Spikes/Scripts/run-g0-sp1-live.sh" >&2
  exit 1
fi

if [[ ! -x "$BUILD_BIN" ]]; then
  swift build --package-path Spikes -c release --product EvidenceValidator
fi
"$BUILD_BIN" "$SP1_SRC"

stage="$(mktemp -d "$STAGING/.promote-sp1.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/sp1"
cp -R "$SP1_SRC/." "$stage/sp1/"
cp "$ENV_SRC" "$stage/environment.json"

mkdir -p "$DEST"
if [[ -d "$DEST/sp1" ]]; then
  mv "$DEST/sp1" "$stage/sp1.previous"
fi
mv "$stage/sp1" "$DEST/sp1"
cp "$stage/environment.json" "$DEST/environment.json"
echo "PROMOTED sp1=$DEST/sp1 environment=$DEST/environment.json"
echo "verdict=$(python3 -c "import json; print(json.load(open('$DEST/sp1/evidence.json'))['verdict'])")"
