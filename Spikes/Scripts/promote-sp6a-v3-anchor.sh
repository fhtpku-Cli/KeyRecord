#!/usr/bin/env bash
# Build namespace-attempt-history-v3.json under the current environment, anchor it in git,
# regenerate SP-6A evidence, and refresh run-all / conclusions for strict validate-phase0.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

env_file="evidence/phase0/environment.json"
history="evidence/phase0/sp6a/namespace-attempt-history-v3.json"
sp6a_out="evidence/phase0/sp6a"
ready_tmp="$(mktemp "${TMPDIR:-/tmp}/sp6a-v3-ready.XXXXXX.json")"
cleanup() { rm -f "$ready_tmp"; }
trap cleanup EXIT INT TERM HUP

build_probe() {
  swift build --package-path Spikes -c release --product Phase0Probe >/dev/null
  echo ".build/release/Phase0Probe"
}

build_validator() {
  swift build --package-path Spikes -c release --product EvidenceValidator >/dev/null
  echo ".build/release/EvidenceValidator"
}

reserve_history() {
  local probe="$1"
  rm -f "$history"
  local attempt ready=false
  for attempt in $(seq 1 11); do
    if "$probe" sp6a-history-anchor \
      --environment "$env_file" \
      --history "$history" \
      --output "$ready_tmp" 2>/dev/null; then
      ready=true
      break
    fi
  done
  if [[ "$ready" != true ]]; then
    echo "failed to reserve 11 namespace attempts into $history" >&2
    exit 1
  fi
  jq -e '.attempts | length == 11' "$history" >/dev/null
  echo "reserved 11 attempts -> $history"
}

anchor_commit_only() {
  if git diff --quiet -- "$history" 2>/dev/null && git ls-files --error-unmatch "$history" >/dev/null 2>&1; then
    echo "history already tracked; skip anchor commit"
    return 0
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "working tree must be clean before anchor commit (commit contract changes first)" >&2
    exit 1
  fi
  git add "$history"
  git commit -m "$(cat <<'EOF'
test(spikes): anchor sp6a namespace history v3

Re-anchor immutable Keychain attempt history under the current phase0 environment without touching the v2 anchor artifact.
EOF
)"
  echo "anchor commit: $(git rev-parse HEAD)"
}

regenerate_sp6a() {
  local probe="$1"
  "$probe" sp6a \
    --environment "$env_file" \
    --output "$sp6a_out" \
    --history-anchor "$history"
  bash Spikes/Scripts/audit-security.sh sp6a "$sp6a_out/security-audit.md"
  (cd "$sp6a_out" && shasum -a 256 -c manifest.sha256)
  echo "regenerated $sp6a_out"
}

refresh_phase0_tail() {
  export KEYRECORD_BINDING_COMMIT="$(git rev-list -1 HEAD --grep='ancestor binding, SP-6A regen')"
  python3 Spikes/Scripts/prepare-raw-phase0.py
  local validator tmp_out commit
  validator="$(build_validator)"
  validator="Spikes/$validator"
  commit="$(git rev-parse HEAD)"
  git add evidence/phase0 Spikes/Scripts/prepare-raw-phase0.py Spikes/Scripts/promote-sp6a-v3-anchor.sh
  if ! git diff --cached --quiet; then
    git commit -m "$(cat <<'EOF'
chore(evidence): seal raw phase0 for conclusion generation

Record remanifested raw root and privacy audit under the current SP-6A v3 / SP-6B evidence tree.
EOF
)"
    commit="$(git rev-parse HEAD)"
  fi
  tmp_src="${TMPDIR:-/tmp}/keyrecord-phase0-raw.$$"
  tmp_out="${TMPDIR:-/tmp}/keyrecord-phase0-conclusions.$$"
  rm -rf "$tmp_src" "$tmp_out"
  mkdir -p "$tmp_src"
  git archive "$commit" evidence/phase0 | tar -x -C "$tmp_src"
  "$validator" generate-conclusions \
    --source "$tmp_src/evidence/phase0" \
    --output "$tmp_out" \
    --source-commit "$commit" \
    --generator-commit "$commit"
  rm -rf "$tmp_src"
  rm -rf evidence/phase0
  mv "$tmp_out" evidence/phase0
  bash Spikes/Scripts/verify-manifests.sh evidence/phase0
  echo "refreshed run-all, privacy, conclusions, manifests (source=$commit)"
}

validate_strict() {
  local validator="$1"
  local phase0="evidence/phase0"
  if [[ -f "$phase0/conclusions.json" ]]; then
    local source_commit raw_tmp
    source_commit="$(python3 -c "import json; print(json.load(open('$phase0/conclusions.json'))['source_evidence_commit_sha'])")"
    raw_tmp="$(mktemp -d)"
    git archive "$source_commit" evidence/phase0 | tar -x -C "$raw_tmp"
    "$validator" validate-phase0 "$raw_tmp/evidence/phase0"
    rm -rf "$raw_tmp"
    "$validator" validate "$phase0"
    echo "strict validate raw+concluded PASS"
  else
    "$validator" validate-phase0 "$phase0"
    echo "strict validate-phase0 PASS"
  fi
}

strict_validate() {
  validate_strict "$1"
}

main() {
  local step="${1:-all}"
  local probe validator
  probe="$(build_probe)"
  probe="Spikes/$probe"

  case "$step" in
    reserve)
      reserve_history "$probe"
      ;;
    anchor)
      anchor_commit_only
      ;;
    sp6a)
      regenerate_sp6a "$probe"
      ;;
    refresh)
      refresh_phase0_tail
      ;;
    validate)
      validator="$(build_validator)"
      strict_validate "Spikes/$validator"
      ;;
    all)
      reserve_history "$probe"
      anchor_commit_only
      regenerate_sp6a "$probe"
      refresh_phase0_tail
      validator="$(build_validator)"
      strict_validate "Spikes/$validator"
      ;;
    *)
      echo "Usage: $0 [reserve|anchor|sp6a|refresh|validate|all]" >&2
      exit 64
      ;;
  esac
}

main "$@"
