# VIA 原始布局几何拒绝规则

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `39e38e836af693fad25f1a658d1e78faded1d705` (PR #55).

## Reproduction and behavior

A raw VIA definition containing an unknown field inside `layouts` still produced
`CanonicalGeometry` and nonzero physical-position counts. The compiled definition
path already withheld geometry for unknown layout fields. This made the two
representations disagree about whether KeyRecord understood the geometry.

The reproduction adds a synthetic `future_geometry` field beside `keymap` and
checks both accepted identity representations, with and without layout options.
The public parser and matching path failed ten assertions before the fix; see
`/private/tmp/keyrecord-via-raw-geometry-red.log`. The fixture does not claim that
an official VIA release supports that synthetic field. It exercises unknown
input handling, using the same conservative policy as compiled definitions.

The raw path now retains the key assignments but marks complex geometry and
withholds coordinates when layout fields are not understood. Known KLE content
is still parsed: an out-of-matrix coordinate remains an error, even with an
unknown layout field. Existing layout-option limitations remain visible.

This is a reference-analysis correctness fix, not a discovered authorization
bypass. File evidence remains device-unknown and deployment-unverified. No hash,
persisted baseline, frozen contract or new gate is introduced.

## Validation

The focused parser suite passes all 13 tests after the fix. Regression coverage
also checks that bindings survive, physical-position counts are zero, and
malformed coordinates are still rejected. A native App regression imports the
files through the actual file reader/model and checks the complex-geometry
explanation in English and Simplified Chinese while retaining the original copy.

The full local verification command is:

```sh
bash Scripts/verify-local.sh --firmware-app-tests
```

Its log is `/private/tmp/keyrecord-via-raw-geometry-local.log`. Push/PR CI and the
merge commit's main CI execute the same native regression plus the existing
official-source oracle suite. Their results are checked separately before the
increment is reported complete.

Self-review covers both identity representations, combined layout/geometry
limitations, unchanged valid raw/compiled fixtures, malformed-input refusal,
preserved key assignments, and native presentation. Production support remains
empty; real browser runtime/importer identity and loaded-definition collection
remain unimplemented. This fix does not establish that provenance link. Real
device, Keychain restore, uninstall and release validation remain deferred;
deletion review remains required.
