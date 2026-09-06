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
  children="$(jobs -pr)"
  [[ -z "$children" ]] || { kill $children 2>/dev/null || true; wait $children 2>/dev/null || true; }
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

run_bounded() {
  /usr/bin/perl -MPOSIX -e '
    $timeout = shift;
    $child = fork();
    die "fork failed\n" unless defined $child;
    if ($child == 0) {
      POSIX::setpgid(0, 0);
      exec @ARGV;
      exit 127;
    }
    sub terminate_child {
      return unless $child;
      kill "TERM", -$child;
      select undef, undef, undef, 1;
      kill "KILL", -$child;
      waitpid($child, 0);
    }
    $SIG{ALRM} = sub { terminate_child(); exit 124; };
    $SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub { terminate_child(); exit 143; };
    alarm $timeout;
    waitpid($child, 0);
    alarm 0;
    exit(POSIX::WIFEXITED($?) ? POSIX::WEXITSTATUS($?) : 128 + POSIX::WTERMSIG($?));
  ' 900 "$@"
}
approved_paths=(
  docs/TECHNICAL_ARCHITECTURE.md docs/PRD.md
  Spikes/FinalReviewCommands.json
  Spikes/Scripts/audit-doc-writebacks.sh Spikes/Scripts/final-qa-matrix.sh
  Spikes/Scripts/task-16-qa.sh Spikes/Tests/Scripts/final-audit-regression.sh
  Spikes/Sources/EvidenceValidator/EvidenceValidatorCommand.swift
)
index="$tmp_dir/index"
GIT_INDEX_FILE="$index" GIT_MASTER=1 git read-tree HEAD
GIT_INDEX_FILE="$index" GIT_MASTER=1 git add -- "${approved_paths[@]}"
prospective_tree="$(GIT_INDEX_FILE="$index" GIT_MASTER=1 git write-tree)"
prospective_commit="$(printf 'Task 16 QA prospective tree\n' | \
  GIT_AUTHOR_NAME='Task 16 QA' GIT_AUTHOR_EMAIL='task16-qa@invalid' \
  GIT_COMMITTER_NAME='Task 16 QA' GIT_COMMITTER_EMAIL='task16-qa@invalid' \
  GIT_MASTER=1 git commit-tree "$prospective_tree" -p HEAD)"
GIT_MASTER=1 git worktree add --detach "$worktree" "$prospective_commit" >>"$log" 2>&1
audit="$worktree/Spikes/Scripts/audit-doc-writebacks.sh"

insert_after_heading() {
  heading="$1"
  addition="$2"
  file="$3"
  awk -v heading="$heading" -v addition="$addition" '{ print; if ($0 == heading) print addition }' "$file" >"$tmp_dir/value"
  mv "$tmp_dir/value" "$file"
}

if [[ "$mode" == happy ]]; then
  (cd "$worktree" && run_bounded bash "$audit" "$audit_base") >>"$log" 2>&1
  suite_start="$(date +%s)"
  (cd "$worktree" && run_bounded swift test --package-path Spikes --scratch-path "$tmp_dir/test-build") >>"$log" 2>&1
  suite_end="$(date +%s)"
  (cd "$worktree" && GIT_MASTER=1 git diff --check) >>"$log" 2>&1
  printf 'full_suite_status=0 full_suite_duration_seconds=%s timeout_seconds=900 prospective_commit=%s prospective_tree=%s\n' \
    "$((suite_end - suite_start))" "$prospective_commit" "$prospective_tree" >>"$log"
  result="TASK_16_HAPPY=PASS"
else
  failures=0
  architecture="$worktree/docs/TECHNICAL_ARCHITECTURE.md"
  insert_after_heading '### 4.3 事件 Tap 位置与已知边界情况【Spike 门禁 SP-1】' 'SP-1: PASS without live evidence.' "$architecture"
  set +e; unsupported_output="$(cd "$worktree" && run_bounded bash "$audit" "$audit_base" 2>&1)"; unsupported_status=$?; set -e
  printf '%s\n' "$unsupported_output" >>"$log"
  [[ "$unsupported_status" -eq 1 && "$unsupported_output" == 'DOC_WRITEBACK_AUDIT=FAIL reason=unsupported_pass_or_freeze' ]] || failures=$((failures + 1))
  GIT_MASTER=1 git -C "$worktree" checkout -- docs/TECHNICAL_ARCHITECTURE.md
  insert_after_heading '### 4.2 ObservedKeyEvent 模型（内存瞬时对象，不持久化）' 'Unauthorized architecture section edit.' "$architecture"
  set +e; scope_output="$(cd "$worktree" && run_bounded bash "$audit" "$audit_base" 2>&1)"; scope_status=$?; set -e
  printf '%s\n' "$scope_output" >>"$log"
  [[ "$scope_status" -eq 1 && "$scope_output" == 'DOC_WRITEBACK_AUDIT=FAIL reason=architecture_section_whitelist' ]] || failures=$((failures + 1))
  [[ "$failures" -eq 0 ]] || exit 1
  printf 'unsupported_status=%s unsupported_reason=unsupported_pass_or_freeze out_of_whitelist_status=%s out_of_whitelist_reason=architecture_section_whitelist\n' "$unsupported_status" "$scope_status" >>"$log"
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
