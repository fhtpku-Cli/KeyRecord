#!/bin/bash
# Use only with the revised offline-only harness. No host capture is authorized.
set -euo pipefail
if [[ $# != 1 ]]; then
    printf 'usage: %s PATH_TO_REVISED_HARNESS\n' "$0" >&2
    exit 1
fi
harness=$1
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
checks=0
run_case() {
    expected=$1
    shift
    actual=0
    "$harness" "$@" > "$scratch/stdout" 2> "$scratch/stderr" || actual=$?
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL exit=%s expected=%s args=%s\n' "$actual" "$expected" "$*" >&2
        cat "$scratch/stderr" >&2
        exit 1
    fi
    checks=$((checks + 1))
}
run_case 0 --help
run_case 0
run_case 0 --mode offline --out "$scratch/receipt.json"
/usr/bin/ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$scratch/receipt.json"
/usr/bin/grep -q '"code" : "offline_fixture_passed"' "$scratch/receipt.json"
for mode in physical synthetic; do
    run_case 2 --mode "$mode" --seconds 30
    /usr/bin/grep -q '"code" : "capture_qualification_unavailable"' "$scratch/stdout"
    /usr/bin/grep -q '"tapCreations" : 0' "$scratch/stdout"
done
run_case 1 --mode typo
run_case 1 --seconds 30
run_case 1 --mode
run_case 1 --help --mode physical
run_case 1 --mode physical --seconds nonsense
run_case 1 --mode physical --seconds 29
run_case 1 --mode physical --seconds 61
run_case 1 --mode offline --seconds 30
run_case 1 --mode offline --mode physical
run_case 1 --mode offline --unknown value
run_case 1 --mode offline --out
run_case 1 --mode offline --out "$scratch/missing/receipt.json"
run_case 1 --out "$scratch/untouched.json" --mode typo
[[ ! -e "$scratch/untouched.json" ]]
printf 'preserve-existing-receipt' > "$scratch/existing.json"
run_case 1 --out "$scratch/existing.json" --mode offline --seconds 30
[[ $(cat "$scratch/existing.json") == preserve-existing-receipt ]]

printf 'PASS harness CLI: %s cases; offline fixture: 6 checks; no live capture\n' "$checks"
