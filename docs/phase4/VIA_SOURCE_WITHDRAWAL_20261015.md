# VIA 版本观测中的来源撤销

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `dd72c829b9e86cdbf4a772fd7db2ebce9e41c334` (PR #56).

## Reproduction

The version-reading flow checked that the selected layout bytes still matched
before and after reports. Clearing or reselecting the layout did not close its
active connection. If the same bytes were selected again before the reply,
the old operation could continue and save a recovery record with its observation.
Byte equality cannot represent withdrawal followed by an identical selection.

The native regression uses the real import model and temporary files, pauses
the first synthetic protocol reply, clears/reselects the same layout, and then
delivers that old reply. Before the fix, the connection stayed open, a second
report was sent and a record was saved in the encrypted ledger. Both clear/reload
and direct reselection reproduced the defect (ten failed assertions), recorded
in `/private/tmp/keyrecord-via-withdrawal-red.log`.

A separate picker regression clears the actual import model while a stubbed
original-bytes accessor continues returning the old bytes. It isolates operation
revocation from data equality. Before the fix, the selected endpoint was opened
and a record was saved (four failed assertions), recorded in
`/private/tmp/keyrecord-via-picker-withdrawal-red.log`. This test uses a synthetic
picker callback, not a user's device picker or actual browser state.

## Fix

The existing import change callback now cancels a pending VIA version read when
the selected original becomes unavailable. It closes the selected connection
immediately and releases the operation's busy state. The read uses the existing
request-identity pattern to check that it still owns the operation before opening,
after returning from the picker, after reports and before retaining the result.
Old completions cannot restore permission merely because the bytes match again,
or clear a newer operation's state. A fresh explicit read remains available.

Changes to the separate definition reference do not cancel a version read while
the original layout is still selected. Withdrawal does not delete retained copies
or interfere with other firmware operations. Once observation has finished and
retention has begun, existing encrypted transaction rules own that operation.

The operation identifier is in-memory state, following the existing Vial read
pattern. No hash, persisted baseline, compatibility contract or new release gate
is added. Ordinary native tests reproduce the failure and verify the fix.

## Validation and boundary

The firmware native suite covers 94 tests: 81 mapping/firmware,
12 VIA import and one production-composition scenario. This includes the two new
regressions, successful fresh reads after cancellation, independent definition
selection while a layout version read is pending, and the existing privacy,
picker, changed-bytes, Vial readback, recovery and uninstall simulations. Debug
build-for-testing and unsigned universal Release builds passed. Logs are
`/private/tmp/keyrecord-via-withdrawal-green-final.log`,
`/private/tmp/keyrecord-via-withdrawal-green-build.log` and
`/private/tmp/keyrecord-via-withdrawal-release.log`.

Self-review checks synchronous source withdrawal, picker reentrancy, request
ownership for cleanup/error paths, preservation of durable copies and the
transition from observation to encrypted retention. Exact-head push/PR CI and the
merge commit's main CI are checked separately before reporting completion.

This fixes the selected-file observation lifetime. It does not implement actual
VIA browser/runtime identity or loaded-definition collection. Importer/schema
axes remain unknown and the production support directory remains empty. Real
device HID, Keychain restoration, actual uninstall and release qualification
remain deferred. Deletion review remains in place.
