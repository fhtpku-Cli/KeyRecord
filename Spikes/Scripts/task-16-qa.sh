#!/usr/bin/env bash
set -euo pipefail

audit_base="2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
mode="${1:-}"
case "$mode" in
  happy) receipt=".omo/evidence/task-16-phase-0-validation.txt" ;;
  failure) receipt=".omo/evidence/task-16-phase-0-validation-failure.txt" ;;
  *) printf 'Usage: %s happy|failure\n' "$0" >&2; exit 64 ;;
esac

root="$(GIT_MASTER=1 git rev-parse --show-toplevel)"
before_head="$(GIT_MASTER=1 git rev-parse HEAD)"
before_tree="$(GIT_MASTER=1 git rev-parse HEAD^{tree})"
before_diff="$(GIT_MASTER=1 git diff | shasum -a 256 | cut -d ' ' -f 1)"
before_cached="$(GIT_MASTER=1 git diff --cached | shasum -a 256 | cut -d ' ' -f 1)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task16.XXXXXX")"
worktree="$tmp_dir/worktree"
publish_temp=""
cleanup() {
  status=$?; trap - EXIT INT TERM HUP
  GIT_MASTER=1 git worktree remove --force "$worktree" >/dev/null 2>&1 || true
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT INT TERM HUP
mkdir -p .omo/evidence
rm -f "$receipt"
publish_temp="$(mktemp ".omo/evidence/.task-16-${mode}.XXXXXX")"
log="$tmp_dir/qa.log"
: >"$log"

GIT_MASTER=1 git worktree add --detach "$worktree" HEAD >>"$log" 2>&1
cp "$root/docs/TECHNICAL_ARCHITECTURE.md" "$worktree/docs/TECHNICAL_ARCHITECTURE.md"
cp "$root/docs/PRD.md" "$worktree/docs/PRD.md"
(cd "$worktree" && GIT_MASTER=1 git add docs/TECHNICAL_ARCHITECTURE.md docs/PRD.md)
audit="$root/Spikes/Scripts/audit-doc-writebacks.sh"

if [[ "$mode" == happy ]]; then
  (cd "$worktree" && bash "$audit" "$audit_base") >>"$log" 2>&1
  (cd "$worktree" && GIT_MASTER=1 git diff --cached --check) >>"$log" 2>&1
  result="TASK_16_HAPPY=PASS"
else
  failures=0
  cp "$root/docs/TECHNICAL_ARCHITECTURE.md" "$worktree/docs/TECHNICAL_ARCHITECTURE.md"
  printf '\nSP-1 PASS without live evidence.\n' >>"$worktree/docs/TECHNICAL_ARCHITECTURE.md"
  set +e; (cd "$worktree" && bash "$audit" "$audit_base") >>"$log" 2>&1; unsupported_status=$?; set -e
  [[ "$unsupported_status" -ne 0 ]] || failures=$((failures + 1))
  cp "$root/docs/TECHNICAL_ARCHITECTURE.md" "$worktree/docs/TECHNICAL_ARCHITECTURE.md"
  printf '\nUnauthorized architecture preface edit.\n' >>"$worktree/docs/TECHNICAL_ARCHITECTURE.md"
  set +e; (cd "$worktree" && bash "$audit" "$audit_base") >>"$log" 2>&1; scope_status=$?; set -e
  [[ "$scope_status" -ne 0 ]] || failures=$((failures + 1))
  [[ "$failures" -eq 0 ]] || exit 1
  printf 'unsupported_status=%s out_of_whitelist_status=%s\n' "$unsupported_status" "$scope_status" >>"$log"
  result="TASK_16_NEGATIVE=PASS"
fi

[[ "$before_head" == "$(GIT_MASTER=1 git rev-parse HEAD)" ]]
[[ "$before_tree" == "$(GIT_MASTER=1 git rev-parse HEAD^{tree})" ]]
[[ "$before_diff" == "$(GIT_MASTER=1 git diff | shasum -a 256 | cut -d ' ' -f 1)" ]]
[[ "$before_cached" == "$(GIT_MASTER=1 git diff --cached | shasum -a 256 | cut -d ' ' -f 1)" ]]
{ printf '%s\nAUDIT_BASE=%s\nCANONICAL_HEAD=%s\nCANONICAL_TREE=%s\n' "$result" "$audit_base" "$before_head" "$before_tree"; cat "$log"; } >"$publish_temp"
mv "$publish_temp" "$receipt"
publish_temp=""
/usr/bin/head -n 1 "$receipt"
