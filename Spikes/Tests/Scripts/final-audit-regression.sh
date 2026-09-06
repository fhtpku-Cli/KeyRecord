#!/usr/bin/env bash
set -euo pipefail

base="2ebc4c1b27a9a334755d7e68c92b06215ac24a11"
expect_reject() {
  set +e
  "$@" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || { printf 'expected rejection: %q ' "$@" >&2; printf '\n' >&2; exit 1; }
}

expect_reject bash Spikes/Scripts/verify-plan-deliverables.sh .omo/plans/phase-0-validation.md Spikes/Tests/Fixtures/FinalAudit/missing-leg
expect_reject bash Spikes/Scripts/audit-source-boundaries.sh --fixture Spikes/Tests/Fixtures/FinalAudit/mutating-vial
expect_reject bash Spikes/Scripts/final-qa-matrix.sh --seed phase0-final --fixture Spikes/Tests/Fixtures/FinalAudit/privacy-leak --output /tmp/keyrecord-final-audit-negative
expect_reject bash Spikes/Scripts/audit-scope.sh "$base" --fixture Spikes/Tests/Fixtures/FinalAudit/out-of-scope-ui
printf 'FINAL_AUDIT_NEGATIVE_FIXTURES=PASS\n'
