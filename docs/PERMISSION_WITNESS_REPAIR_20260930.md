# Tri-state permission witness repair

Before another permission trial, source inspection found that both the collecting
poll and closed-state sampler converted InputMonitoringStatus into a Boolean.
Denied and unknown therefore produced the same `inputMonitoringPreflightNotGranted`
cause. Historical records with that cause remain ambiguous; they are not evidence
of an explicit denial.

A failing-first two-case product run timed out waiting for distinct denied and
unknown observations (four reported failures, including the timeout errors).
The Debug recorder now accepts an exhaustive granted/denied/unknown enum and
emits three fixed causes in the existing boundaryCause field. Both product call
sites use one exhaustive adapter. No new serialized field, permission query or
input trace is added, and recording still requires the opt-in Debug journal.

Focused package tests pass. The complete package run passes all 590 XCTest cases.
A quiet product run passes all 61 cases, including closed-state denied and unknown
observations and no automatic reopening. That quiet pass did not erase an earlier
intermittent recovery failure, which was separately reproduced and repaired in
[the recovery settlement repair](RECOVERY_SETTLEMENT_REPAIR_20260930.md).

Logs are `/private/tmp/keyrecord-permission-witness-{red,focused,package,product,product-quiet}.log`.
The initial unsigned arm64 Release build and zero-match static network audit pass;
the permission enum and recording methods are absent from its symbol table.
This observation-only repair does not qualify live permission revocation,
protected-read coverage, the hosted observer or a collecting Release.
