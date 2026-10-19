# VIA 文件编辑正式入口

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

The user-selected workflow is a fresh VIA export, local editing in KeyRecord,
and a separate file manually imported through VIA. It does not require a browser
instance binding, a browser extension or a maintained VIA fork.

## Reproduction and behavior

The native entry on main `56cdcb7` retained a valid export but could not expose
the editor without independent importer/device qualification. A real native
button test reproduced two failed assertions: generation was unavailable and
the staging control did not exist. The earlier test setup without a window was
corrected before recording this behavioral reproduction.

The entry now retains an encrypted original with an explicit, optional
`viaFile` compatibility basis. File facts remain separate from device and
importer axes: missing device protocol, definition and importer versions remain
nil. Old records without the new field retain their prior qualification rules;
metadata inside an imported JSON file cannot create this basis. Vial and the
empty production device support directory retain their existing behavior.

The file path validates name, nonzero 32-bit VID/PID, 1–32 equal-size nonempty
layers, string keycodes/macros and optional encoder pairs with matching layer
counts. It supports 90 basic output keycodes: letters, digits, F1–F20 and the
listed standard control/navigation/modifier keys. The existing standard-output
check also applies. Official VIA's `KC_RGHT` name is recognized as right arrow.

Changes remain limited to selected JSON string ranges. Device ID, topology,
macros, encoders, unknown actions and other fields are not rewritten. Unknown
actions cannot be selected for replacement, including raw numeric spellings;
they remain opaque when untouched. This is not a claim that arbitrary preserved
extensions are understood or accepted by every future importer. Layer/reset
entry protection, automatic-empty-slot restrictions, unique slots, layer
reachability, latest retained original, preview and export transactions remain.
File reachability only interprets supported, well-formed layer-entry syntax.
Unsupported structures can still be retained/exported as recovery originals,
with editing disabled and an explicit explanation.

The production button exposes staging, preview and export without fixture
support entries. English and Chinese copy identify file scope, the need to
export a fresh copy after other VIA edits, and manual import/keyboard checking.
File positions do not become physical geometry. Export remains
`awaitingUserImport`; claiming import does not set a verification timestamp.
The existing explicit behavior-test confirmation and recovery/deletion review
are unchanged.

## Executed offline validation

- Native reproduction followed by actual retain/stage/preview/export buttons,
  both language explanations, stale privacy/source rejection, encrypted reopen
  and unsupported-file recovery retention. The related native suite has 102
  scenarios, using temporary stores and synthetic host dependencies.
- Core tests cover byte-preserving output, interruption after external export
  followed by encrypted reconciliation, old records, forged metadata, wrong
  backend/axes, malformed structures, unknown/protected entries, occupied
  automatic slots and malformed layer references.
- The existing official VIA oracle obtains the actual output list from Swift,
  exports all 90 replacements through the encrypted public transaction, and
  executes the unchanged official `isViaSaveFile` and `loadLayout` function
  bodies extracted from the pinned VIA source AST. Synthetic FileReader and
  device sinks capture calls; no browser or HID is opened. Nine dictionary
  variants cover protocols 7–12 and protocol 13 keycode versions 0, 8 and 9.
  Tests check actual basic-key conversions, macro/encoder preservation, and
  official rejection of wrong device, key counts and macro counts.
- Local full package validation passed all 797 tests; the final 33 firmware
  transaction tests passed after adding the interrupted-export case.
  Existing official Vial oracles, unsigned builds and native CI
  remain required. The existing privacy schema audit registers only the new
  enum and operation field; no macro/key content is added to journal metadata.

Self-review found and corrected two output-list mismatches before submission:
F21–F24 are outside the existing standard-output set, and VIA uses `KC_RGHT`,
not `KC_RIGHT`. The initial full package run caught the missing privacy schema
registration; its assertions were retained and registration was completed.

Logs use `/private/tmp/keyrecord-via-file-*`; temporary logs can expire. The
regressions and oracle are committed and executed by CI. No new hash, frozen
contract, baseline or gate was introduced.

## Remaining boundary

The file edit range is now usable from production composition; this does not
qualify any physical keyboard or importer runtime. Real VIA import/effects,
device HID, Keychain recovery, uninstall and release validation remain deferred.
Vial readback still requires qualified device support. Missing physical layout
definitions do not produce geometry or physical-benefit claims.
