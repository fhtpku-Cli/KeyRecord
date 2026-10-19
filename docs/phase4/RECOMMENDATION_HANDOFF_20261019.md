# 推荐到后端草稿衔接

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

## Failure and resulting behavior

The production recommendation callback previously existed only for Karabiner and immediately staged a draft. Without a selected profile the intent was lost. VIA/Vial had no handoff from recommendations to their separate file editors.

The production callback now captures its backend and opens a transient settings request containing the exact output, trigger and scope. Karabiner waits for a selected profile, then stages the original combination and application condition. Staging does not apply a configuration or bypass conflict and risk checks.

The firmware handoff supports only global basic key replacements within the existing output vocabulary. It refuses modifier combinations and application-specific requests with English/Chinese explanations. It never removes modifiers, changes scope, guesses a position, or claims a file position is physical key evidence. A manual basic replacement also affects the selected key when modifiers are held; the confirmation explains this difference.

The user chooses a current compatible encrypted copy and then one matching original position/layer. Standard key aliases share the existing parser. Multiple matching positions require a choice. The selected change and every existing draft change pass through the real patch preview before staging. Duplicate draft positions are refused instead of overwritten; existing changes survive. Protected entries, unreachable layers, original freshness and output compatibility are rechecked on preview/export. Unknown Vial device/version combinations remain unavailable; production support remains empty.

Requests are cleared on cancellation, backend switch and privacy closure. Captured callbacks cannot retarget a different backend. Async staging checks current request, session, original and draft contents again before publishing. This adds no persistent schema, hash, frozen contract, baseline or gate.

## Offline observation

- Package tests cover exact Karabiner shortcut/application intent, every modifier family, Fn unknown, stateful requests, aliases, multiple layers/positions, duplicate positions, existing draft preservation, protected entries, unreachable layers, backend mismatch, stale originals and absent Vial/output support.
- Native tests exercise the actual ProductScreens recommendation button through settings into Karabiner staging or a VIA refusal. Missing-profile intent survives until selection. Cancellation, backend switching, privacy closure and stale asynchronous completion leave drafts unchanged.
- English/Chinese native AX actions select a VIA copy and position, stage the before/after preview and export the resulting file through the existing model. The selected position changes from KC_A to KC_C, the other position and opaque macro bytes remain unchanged, and the result stays awaiting manual import without verification evidence.
- Synthetic Vial support permits only its qualified fixture; the default production directory rejects the same request. Native screenshot inspection confirms readable selection and original/output labels in the handoff card.

Reproduction commands: `swift test`; unsigned `xcodebuild ... build-for-testing`; `Scripts/test-firmware-native.sh <built KeyRecordAppTests.xctest> <temporary QA directory>`. CI retains the official offline compatibility comparisons, package tests, capture harness and unsigned builds. Local artifacts are temporary and contain synthetic fixtures only.

Local results: 812 package tests and 115 native regression tests passed (95 mapping/file-flow, 18 VIA import, two production composition/quit tests), plus the unsigned Debug test build. Self-review covered semantic preservation, default-empty support, the real patch path, duplicate/stale draft refusal and privacy invalidation; no blocking finding remains. Local screenshot output: `/private/tmp/kr-recommendation-qa/recommendation-position-{en,zh-Hans}.png`.

## Remaining boundaries

Real Karabiner application effects/reload/disable timing, VIA GUI import and keyboard effects, Vial HID/device qualification, Keychain recovery, uninstall and public release validation remain deferred. Configuration copies and synthetic support do not qualify those behaviors. Deletion review and recovery copies remain in place. The next separate offline scope is connecting complete physical-evidence sources; this batch does not start it or restore scheduled work.
