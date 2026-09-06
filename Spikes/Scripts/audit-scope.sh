#!/usr/bin/env bash
set -euo pipefail
expected_base="2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
base="${1:-}"
shift || true
[[ "$base" == "$expected_base" ]] || { printf 'SCOPE_AUDIT=FAIL reason=audit_base\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-scope.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
GIT_MASTER=1 git merge-base --is-ancestor "$base" HEAD || { printf 'SCOPE_AUDIT=FAIL reason=base_not_ancestor\n' >&2; exit 1; }

if [[ "${1:-}" == "--fixture" && $# -eq 2 ]]; then
  fixture="$2"
  [[ -f "$fixture/changed-paths.txt" && ! -L "$fixture/changed-paths.txt" ]] || { printf 'SCOPE_AUDIT=FAIL reason=invalid_fixture\n' >&2; exit 1; }
  cp "$fixture/changed-paths.txt" "$tmp_dir/paths"
elif [[ $# -eq 0 ]]; then
  GIT_MASTER=1 git diff --name-only "$base" HEAD >"$tmp_dir/paths"
else
  printf 'Usage: %s AUDIT_BASE [--fixture PATH]\n' "$0" >&2; exit 64
fi

while IFS= read -r path; do
  case "$path" in
    .gitignore|docs/TECHNICAL_ARCHITECTURE.md|docs/PRD.md|Spikes/*|evidence/phase0/*) ;;
    *) printf 'SCOPE_AUDIT=FAIL reason=out_of_scope path=%s\n' "$path" >&2; exit 1 ;;
  esac
done <"$tmp_dir/paths"
if GIT_MASTER=1 git ls-files -z | tr '\0' '\n' | /usr/bin/grep -Eq '(^|/)\.DS_Store$|^\.omo(/|$)'; then
  printf 'SCOPE_AUDIT=FAIL reason=forbidden_tracked_path\n' >&2; exit 1
fi
if /usr/bin/grep -Eq '\.package[[:space:]]*\(' Spikes/Package.swift; then printf 'SCOPE_AUDIT=FAIL reason=dependency_drift\n' >&2; exit 1; fi
bash Spikes/Scripts/audit-doc-writebacks.sh "$base" >/dev/null
printf 'SCOPE_AUDIT=PASS base=%s paths=%s dependencies=system-only\n' "$base" "$(wc -l <"$tmp_dir/paths" | tr -d ' ')"
