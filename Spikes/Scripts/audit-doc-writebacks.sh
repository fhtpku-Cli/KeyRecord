#!/usr/bin/env bash
set -euo pipefail
expected_base="2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
base="${1:-}"
[[ "$base" == "$expected_base" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=audit_base expected=%s actual=%s\n' "$expected_base" "${base:-missing}" >&2; exit 1; }
GIT_MASTER=1 git cat-file -e "$base^{commit}" 2>/dev/null || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=missing_base\n' >&2; exit 1; }
GIT_MASTER=1 git merge-base --is-ancestor "$base" HEAD || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=base_not_ancestor\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-docs.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

architecture="docs/TECHNICAL_ARCHITECTURE.md"
prd="docs/PRD.md"
for path in "$architecture" "$prd"; do
  [[ -f "$path" && ! -L "$path" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=invalid_doc path=%s\n' "$path" >&2; exit 1; }
  GIT_MASTER=1 git show "$base:$path" >"$tmp_dir/base-$(basename "$path")"
done

GIT_MASTER=1 git diff --name-only "$base" -- docs | LC_ALL=C sort >"$tmp_dir/changed-docs"
printf '%s\n' "$architecture" "$prd" | LC_ALL=C sort >"$tmp_dir/allowed-docs"
comm -23 "$tmp_dir/changed-docs" "$tmp_dir/allowed-docs" >"$tmp_dir/disallowed-docs"
[[ ! -s "$tmp_dir/disallowed-docs" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=doc_path path=%s\n' "$(/usr/bin/head -n 1 "$tmp_dir/disallowed-docs")" >&2; exit 1; }

normalize_architecture() {
  awk '
    function allowed_heading(line) {
      return line ~ /^### (4\.[345]|5\.[234]|9\.[123]|14\.3)([^0-9]|$)/ || line ~ /^## (13|15)([^0-9]|$)/
    }
    /^## / || /^### / {
      if (allowed_heading($0)) { allowed=1; print "__ALLOWED_SECTION__ " $2; next }
      allowed=0
    }
    allowed { next }
    /^\| ADR-(002|003|005|006|007|009|011|013) \|/ { print "__ALLOWED_ADR_ROW__ " $2; next }
    { print }
  ' "$1"
}
normalize_prd() {
  awk -F "|" 'BEGIN { OFS="|" }
    /^\| O[1-7] \|/ { $4=" __STATUS_ANNOTATION__ "; print; next }
    { print }
  ' "$1"
}
normalize_architecture "$tmp_dir/base-TECHNICAL_ARCHITECTURE.md" >"$tmp_dir/base-architecture"
normalize_architecture "$architecture" >"$tmp_dir/current-architecture"
cmp -s "$tmp_dir/base-architecture" "$tmp_dir/current-architecture" || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=architecture_section_whitelist\n' >&2; exit 1; }
normalize_prd "$tmp_dir/base-PRD.md" >"$tmp_dir/base-prd"
normalize_prd "$prd" >"$tmp_dir/current-prd"
cmp -s "$tmp_dir/base-prd" "$tmp_dir/current-prd" || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=prd_requirement_or_nonstatus_edit\n' >&2; exit 1; }

GIT_MASTER=1 git diff "$base" -- "$architecture" "$prd" | awk '/^\+\+\+/{next} /^\+/{sub(/^\+/, ""); print}' >"$tmp_dir/additions"
if /usr/bin/grep -Eiq 'G0[ :：]*(PASSED|PASS)|SP-(1|2|3|4B|5A|5B|6A|6B)[ :：]*(PASSED|PASS)|production (API|dependency).*(frozen|freeze)|生产.*(API|依赖).*已冻结' "$tmp_dir/additions"; then
  printf 'DOC_WRITEBACK_AUDIT=FAIL reason=unsupported_pass_or_freeze\n' >&2; exit 1
fi

expected_conclusions="aabf4f8adbaf03253fdf7eb250ffc69b7cbb3f6616015dc170f6d6c395e9d5ab"
[[ "$(shasum -a 256 evidence/phase0/conclusions.json | cut -d ' ' -f 1)" == "$expected_conclusions" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=conclusions_hash\n' >&2; exit 1; }
/usr/bin/grep -Eo 'evidence/phase0/[A-Za-z0-9._/-]+' "$tmp_dir/additions" | LC_ALL=C sort -u >"$tmp_dir/evidence-paths" || true
[[ -s "$tmp_dir/evidence-paths" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=no_evidence_references\n' >&2; exit 1; }
while IFS= read -r path; do
  [[ -f "$path" && ! -L "$path" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=unresolved_evidence path=%s\n' "$path" >&2; exit 1; }
  directory="$(dirname "$path")"
  name="$(basename "$path")"
  manifest="$directory/manifest.sha256"
  [[ -f "$manifest" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=missing_reference_manifest path=%s\n' "$path" >&2; exit 1; }
  expected_hash="$(awk -v name="$name" '$NF == name { print $1 }' "$manifest")"
  actual_hash="$(shasum -a 256 "$path" | cut -d ' ' -f 1)"
  [[ -n "$expected_hash" && "$expected_hash" == "$actual_hash" ]] || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=reference_manifest_drift path=%s\n' "$path" >&2; exit 1; }
done <"$tmp_dir/evidence-paths"

required=(
  'G0：OPEN' 'SP-4A：PASS（仅定义 schema）' '未版本化' '合成夹具'
  '不是字面只读' 'SP-5A 与 SP-5B' 'O6：OPEN' 'Fn 实机恢复'
  'O7：保守失败关闭' 'dependency_frozen=false' 'Intel 实机计时仍阻塞'
  '生产 API 与生产依赖均未冻结' 'G1' 'KARABINER_STABLE' 'VIA_GENERATION'
  'VIAL_BETA' 'FULL_BACKUP_FINAL_RELEASE'
)
for phrase in "${required[@]}"; do
  /usr/bin/grep -Fq "$phrase" "$architecture" || { printf 'DOC_WRITEBACK_AUDIT=FAIL reason=missing_status phrase=%s\n' "$phrase" >&2; exit 1; }
done
jq -e '.g0.status == "OPEN" and ((.spikes[] | select(.id=="SP-6B") | .dependency_frozen) == false) and ([.downstream_blocks[].id] | sort) == (["G1","KARABINER_STABLE","VIA_GENERATION","VIAL_BETA","FULL_BACKUP_FINAL_RELEASE"] | sort)' evidence/phase0/conclusions.json >/dev/null
printf 'DOC_WRITEBACK_AUDIT=PASS base=%s evidence_refs=%s\n' "$base" "$(wc -l <"$tmp_dir/evidence-paths" | tr -d ' ')"
