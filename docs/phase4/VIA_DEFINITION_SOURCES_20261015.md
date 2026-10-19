# VIA 定义来源与选择绑定的版本读取

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `c2254477fcc378fad52c6b604b753165968afac5`.

## Reproduced gaps

The official VIA site serves compiled definitions with decimal `vendorProductId`
and `layouts.keys` / `layouts.optionKeys`. The existing parser accepted only
`layouts.keymap`. A synthetic definition transformed and validated by the official
reader therefore failed with `invalidGeometry` through the public Swift parser.
The red result is in `/private/tmp/keyrecord-via-definition-red.log`.

The native "retain VIA copy and read device versions" path also lacked the
current-selection check already used by ordinary copy retention. With no current
file, or after withdrawing it inside the device picker, the action still opened
the simulated endpoint and saved the old copy. The native red test recorded eight
assertion failures in `/private/tmp/keyrecord-via-selection-red.log`.

## Changes

- Read both raw KLE and compiled VIA definition representations. For simple
  compiled keys, matrix coordinates and key centers agree with the official raw
  definition transformation. Identity and every saved layer's matrix size still
  must match. Mixed representations, malformed dimensions/coordinates, duplicate
  simple-key positions and malformed option collections are rejected.
- Preserve conservative geometry handling: options, rotations, decals, encoders,
  secondary shapes and unknown key/layout fields do not produce measured geometry.
  File reference evidence remains device-unknown and deployment-unverified.
- Recheck the selected original before opening a VIA connection, through picker
  authorization, after each report, and before retention. Withdrawal or replacement
  by different bytes (including the same VID/PID) discards the observation and
  closes the connection without creating a recovery record.
- Display the definition version required by the independently observed device
  protocol: supported protocols 7-10 require v2, 11-13 require v3. This derived
  requirement does not populate `definitionSchema` or `importer`. The UI explicitly
  explains that a selected definition copy does not identify the online runtime's
  currently loaded definition.

No new hash, frozen contract, baseline or gate was added. The selection fix reuses
the existing byte comparison, authorization callback and encrypted transaction.
Deletion review, recovery originals and the empty production support directory
remain in force. No new product network capability was introduced.

## Official source evidence

The official [VIA definition loader](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/utils/device-store.ts)
fetches `/definitions/{v2|v3}/{vendorProductId}.json`; the official
[device discovery code](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/store/devicesThunks.ts)
chooses v3 at protocol 11. That app revision was rechecked against upstream HEAD.
`Scripts/via-definition-oracle.cjs` executes the published `@the-via/reader@1.14.4`
V2/V3 transformation and validation functions, plus the unchanged official
definition-selection expression. Its synthetic fixture is consumed by Swift and
native tests. The corresponding reader source is
[c260099](https://github.com/the-via/reader/tree/c26009992a7a2e9776720ebf5644a50f8e92c7a5).

```sh
npm install --prefix /private/tmp/keyrecord-via-reader-runtime --ignore-scripts --no-audit --no-fund @the-via/reader@1.14.4
node Scripts/via-definition-oracle.cjs \
  /private/tmp/keyrecord-via-reader-runtime/node_modules/@the-via/reader \
  /private/tmp/keyrecord-official-via-app /private/tmp/via-compiled-definitions.json
swift test --filter 'VIAReferenceParserTests|VialVerificationScopeTests'
```

Read-only HTTP inspection on 2026-10-15 confirmed that the current
`usevia.app/definitions/supported_kbs.json` contains v2/v3 catalogs and index
`version: "0.1.0"`; a v3 definition response uses the compiled representation.
The current HTML still exposes `definition_hash` and bundled asset filenames,
without an importer runtime version in the page/header metadata inspected.

The index version describes the catalog, the reader package version describes a
dependency, and a definition's `firmwareVersion` describes firmware-facing data.
None identifies the importer executing in a user's browser tab. Likewise, a
download path or schema requirement does not establish which definition that tab
actually loaded: custom definitions and cached data can differ. These facts are
kept separate, and no version is inferred from VID/PID alone or a claimed field
inside the user's export. Reliable online-runtime/importer identity and loaded
definition provenance therefore remain outstanding. No page script was executed.

## Validation and remaining boundary

Validation covers the official oracle, malformed/mixed/unknown compiled geometry,
protocol requirement boundaries, forged file version claims, actual native file
import and summary display, current selection/picker/late-response invalidation,
encrypted absence of stale recovery records, production composition, the full
package suite and unsigned native build. Native execution uses synthetic
endpoints; CI executes package tests and unsigned builds separately.

Local results: all 785 package tests passed; the final 14 focused tests passed
after the unknown-layout review fix; unsigned arm64 build-for-testing succeeded.
The native mapping and VIA import suites passed 89 scenarios, with the separate
production-composition scenario also passing.

Self-review checks that compiled definitions cannot grant version qualification,
unsupported geometry cannot enter physical measurements, source selection remains
valid across the existing device-read authorization boundaries, and deletion and
recovery rules are unchanged. Raw temporary logs use
`/private/tmp/keyrecord-via-definition-*` and `/private/tmp/keyrecord-via-selection-*`.

Real devices, real Keychain restoration, actual uninstall and release qualification
remain deferred. This increment closes the two reproduced offline gaps and advances
source handling; it does not declare Phase 3/4 qualification or all remaining
offline engineering complete. Push/PR CI and the exact merge's main CI are checked
separately before completion.
