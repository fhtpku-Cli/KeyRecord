# 固件缺失层引用的重复扫描修复

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

A file can stay below the existing 8 MiB / 100,000 collection-element limits
while containing thousands of `MO(31)` references and only two actual layers.
Checking each reference previously scanned every slot again to establish that
layer 31 was absent. This made layer reachability quadratic in slot count.
The synchronous patch path is also used by the native model's preview/export
operations on the main actor.

## Measured reproduction

The same Debug test was run before and after the production change, on the
same host. Each sample performs four patch attempts: a valid layer-zero edit
and an unreachable layer-one edit, in both manual and automatic mode. The
timed block also reparses successful outputs and checks their values.

| Missing-layer references | Total slots | Before | After |
| --- | --- | --- | --- |
| 1,000 | 2,002 | 0.266 s | 0.180 s |
| 4,000 | 8,002 | 2.082 s | 0.714 s |
| 16,000 | 32,002 | 24.756 s | 2.893 s |

These are local offline measurements, not a real-device or native UI latency
claim. The regression records elapsed time without a machine-dependent pass
threshold. Its assertions verify unchanged behavior and preserved original
bytes; the old implementation passes those assertions but takes much longer.

## Change and review

Reachability now constructs a set of existing layer numbers once per traversal
and uses set membership for each reference. Both backends use the same layer
existence rule as before. Entry parsing, manual/automatic reachability rules,
protected keys, output checks and transaction logic are unchanged. No input
limit is relaxed and no new hash, frozen contract, baseline or gate is added.

Temporary measurement and package logs use
`/private/tmp/keyrecord-reachability-*`. The regression is part of the existing
package suite and therefore runs in push, PR and main CI. Real HID, Keychain
recovery, uninstall and release validation remain deferred; deletion review
remains required.

The full local package suite passed all 799 tests after the change.
