# Vial 验证范围与导入器版本来源

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `4a4ea969ccc0916cb0372a1dfcd5444484e898ad`.

## Reproduced failure

A saved Vial document can restore macros, tap dance, combos, key overrides,
alternate repeat keys, layout options and settings as well as the key matrix and
encoders. KeyRecord previously reported `verified` after comparing only matrix
and encoder observations, even when the saved document contained other sections.
The public encrypted transaction regression failed before the fix: expected
`partiallyVerified`, observed `verified`.

`Scripts/vial-official-roundtrip.py --scope-probe` executes the unmodified official
save/restore methods against recorder ports. Restoring six opaque/layout sections
changes their values without changing any keymap value. These recorder ports prove
the top-level restoration scope, not the dynamic subprotocol implementations.
The oracle is [vial-gui keyboard_comm.py](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/keyboard_comm.py).

## Resulting behavior

- Matching matrices and encoders produce `partiallyVerified` when the document
  contains any other top-level section. Empty, null and unknown future sections
  also remain unverified; their presence cannot be inferred away from keymap data.
- Version/identity metadata and matrix/encoder sections are the bounded known
  scope. A document containing only those sections retains the existing matching
  result. Baseline and external-change classification still compare every matrix
  and encoder value and retain their existing failure states.
- Unverified section names are stored inside the existing encrypted journal and
  pending operation. Optional fields preserve decoding of earlier records. Loading
  old successful Vial records recomputes scope from the authenticated original;
  old pending evidence replay also returns the corrected scope. There is no silent
  promotion from partial to complete verification on load.
- English and Chinese UI show partial verification and explain that dynamic
  sections remain unverified. Repeat readback and guided rollback still work.
  Partial evidence never authorizes original-copy deletion; deletion review remains.
- Patching preserves opaque sections byte-for-byte. This increment adds no firmware
  writes and does not implement or claim dynamic configuration readback.

## Independent importer metadata

The production composition now locates the Vial application using its official
bundle identifier `today.vial` and reads its version/build from `Contents/Info.plist`.
The identifier comes from [official mac.json](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/build/settings/mac.json).
Reads are bounded to 64 KiB, regular-file-only and reject a symlink at the plist.
Missing, foreign or malformed metadata leaves the importer unknown. No application
is launched and no information is taken from the imported configuration's claimed
importer field. This is version metadata, not signature or device qualification.

The Vial reader supplies its implemented definition-schema name; file format and
claimed protocol values remain file-derived until the existing independent device
reader checks them. VIA's external importer/version facts remain unknown.
Retained records capture the importer version. A changed or missing importer makes
them incompatible, including after the export picker and during readback selection
or completion. Support entries remain empty by default: metadata cannot grant support.

## Offline evidence

- `/private/tmp/keyrecord-dynamic-red.log`: public-path false-complete reproduction.
- `/private/tmp/keyrecord-dynamic-core-final.log`: 87 selected package tests pass,
  including scope/preservation, old journal replay, readback, privacy and boundaries.
- `/private/tmp/keyrecord-dynamic-official.log`: official save, scope probe and
  restore/save of the KeyRecord-patched output pass.
- `/private/tmp/keyrecord-dynamic-probe.log`: public Swift API retains, exports,
  claims import, reads 14 simulated matrix slots, records partial verification and
  reopens encrypted state.
- `/private/tmp/keyrecord-dynamic-native-build.log` and
  `/private/tmp/keyrecord-dynamic-native.log`: unsigned arm64 test build and 73 native
  mapping workflow tests pass, including scope text and temporary importer metadata.
- `/private/tmp/keyrecord-dynamic-host.log`: production composition dependency test
  passes. It waits for initial backend restoration to finish before selecting a
  target, matching the UI's existing busy state; all connection assertions remain.

All importer bundles, configurations, keys and device reports in this validation
are synthetic. Real HID, Keychain restore and uninstall remain deferred; G3/G4 are
not qualified. No new hash, baseline, frozen contract or gate is introduced. Final
push/PR CI and exact post-merge main CI are recorded separately.
