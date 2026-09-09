#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
STAGING="${1:-/tmp/keyrecord-g0-attempt}"
DEST="$REPO_ROOT/evidence/phase0"
SP2_SRC="$STAGING/sp2"
ENV_SRC="$STAGING/environment.json"
BUILD_BIN="$REPO_ROOT/Spikes/.build/release/EvidenceValidator"

[[ -d "$SP2_SRC" ]] || { echo "missing sp2 evidence: $SP2_SRC" >&2; exit 1; }
[[ -f "$ENV_SRC" ]] || { echo "missing environment: $ENV_SRC" >&2; exit 1; }

expected="$(python3 -c "import json; print(json.load(open('$SP2_SRC/evidence.json'))['legs'][0]['environmentSha256'])")"
actual="$(python3 -c "import hashlib; print(hashlib.sha256(open('$ENV_SRC','rb').read()).hexdigest())")"
if [[ "$expected" != "$actual" ]]; then
  echo "environment hash mismatch expected=$expected actual=$actual" >&2
  echo "Re-run: bash Spikes/Scripts/run-g0-sp2-live.sh" >&2
  exit 1
fi

if [[ ! -x "$BUILD_BIN" ]]; then
  swift build --package-path Spikes -c release --product EvidenceValidator
fi
"$BUILD_BIN" "$SP2_SRC"

stage="$(mktemp -d "$STAGING/.promote-sp2.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/sp2"
cp -R "$SP2_SRC/." "$stage/sp2/"
cp "$ENV_SRC" "$stage/environment.json"

mkdir -p "$DEST"
if [[ -d "$DEST/sp2" ]]; then
  mv "$DEST/sp2" "$stage/sp2.previous"
fi
mv "$stage/sp2" "$DEST/sp2"
cp "$stage/environment.json" "$DEST/environment.json"
echo "PROMOTED sp2=$DEST/sp2 environment=$DEST/environment.json"
echo "verdict=$(python3 -c "import json; print(json.load(open('$DEST/sp2/evidence.json'))['verdict'])")"
echo "o6=$(python3 -c "import json; print(json.load(open('$DEST/sp2/evidence.json'))['o6Status'])")"
