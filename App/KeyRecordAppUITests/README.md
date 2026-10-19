# 原生 UI 测试目标

核对日期：2026-10-20。本轮 v1 开发状态见当前项目说明；本文说明已有测试入口及证据范围。

- `KeyRecordAppUITests/Phase1FlowTests.swift` 使用 DEBUG 专用 `KEYRECORD_FLOW_FIXTURE`、内存替身和临时存储，属于签名宿主 XCUITest 场景。文件存在或编译通过不代表全部场景在签名宿主上执行。
- `KeyRecordAppTests` 是另一个测试目标，覆盖原生组件、可访问性、渲染、产品组合、存储/恢复、后端及文件流程。hostless 执行与显式启用的真实 Keychain 用例有不同副作用和证据范围。
- 当前 CI 使用 `Scripts/verify-local.sh --firmware-app-tests`，实际执行 `Scripts/test-firmware-native.sh` 选择的固件/映射、导入和生产组合离线子集，不能说 CI 只构建或执行了全部 App/XCUITest。
- 默认 `Scripts/verify-local.sh` 执行完整 hostless App 测试；`--build-only` 才跳过 App XCTest。构建、阻塞、跳过和实跑成功需分开记录。

限定 Phase 1 的[用户协助走查](../../docs/RELEASE_NATIVE_UI_PREP_20261001.md)保留原候选范围，不追认整个 XCUITest 目标或新增页面。第七批 130 项原生离线回归属于对应提交，不是永久数量要求。

当前阶段及后置真实验证见[项目状态](../../docs/PROJECT_STATUS.md)，通用命令见[README](../../README.md#build-and-test)。
