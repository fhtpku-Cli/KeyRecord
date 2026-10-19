# VIA 当前定义选择的离线证据

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `7cdc7e227422b18194305ad2ae60c86da979834e`, after PR #54 and its main CI passed.

## Reproduced source ambiguity

The official VIA catalog cannot identify the definition selected by the current
runtime. Executing the official selectors with a synthetic catalog and a custom
definition sharing VID/PID selects the custom definition, including a different
matrix position. Substituting the assumption that the catalog was active caused
an assertion failure showing `custom-v3` and column 3 instead of `catalog-v3`
and column 0. The reproduction log is
`/private/tmp/keyrecord-via-catalog-assumption-red.log`.

This is an executable rejection of an unsafe candidate source, not a discovered
production authorization bypass: KeyRecord already leaves these VIA axes unknown.

## Official execution and automated regression

`Scripts/via-session-oracle.cjs` extracts the named selector declarations with the
TypeScript parser, without rewriting their bodies, then transpiles and executes
them with real Redux `createSelector`. It does not import the application's HID,
device API, IndexedDB, telemetry or browser UI modules. Inputs are synthetic state
objects, not a user's browser state. Redux 2.3.0 and TypeScript 5.6.2 match the
official checkout's lockfile and are CI/test dependencies only.

The official [definition selectors](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/store/definitionsSlice.ts)
and [device selectors](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/store/devicesSlice.ts)
are exercised in ten scenarios:

1. Catalog selection with a ready selected device.
2. Custom content overriding the same catalog VID/PID and definition generation.
3. Custom v2 content not overriding v3, followed by selecting the required v2.
4. Separate session states selecting different content for equal VID/PID.
5. Selecting another same-model device retaining a definition while readiness is
   false; layout options from the old device path do not carry over.
6. Disconnect removing the active definition even if cached content and a stale
   ready path remain. A ready flag alone cannot establish a connected source.
7. Deselecting the device removing the active definition.
8. A missing required definition generation not falling back to another one.
9. Replacing definition content under unchanged device identity and display name.
10. Layout options changing effective keys without replacing the definition object.

The existing oracle runner now executes these cases on every push/PR/main CI,
alongside the 11 fixture comparisons and nine encrypted transaction round trips.
Local execution of the expanded pipeline passed; the final selector additions
were rerun successfully. No product code, compatibility data or safety rules change.

```sh
node Scripts/via-session-oracle.cjs /path/to/via-app /path/to/node_modules
```

The second argument must contain `@reduxjs/toolkit@2.3.0` and `typescript@5.6.2`.
For the complete runner, `--via-store-dependencies` can point at that directory;
otherwise it uses the node_modules directory containing the supplied VIA reader.

## What a real source still needs

An integration must observe the actual selected and connected device, readiness,
required definition generation, effective definition and selected layout options
from the same runtime state. A later observation must invalidate old results when
that runtime closes/reloads, selection changes, or the effective content changes.
Those are requirements derived from executed source behavior, not a new persisted
contract or a promise that an arbitrary JSON payload proves provenance.

The official [layout export](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/components/panes/configure-panes/save-load.tsx)
does not carry a runtime identity, importer build or active definition body.
The [store](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/store/index.ts)
exports its state to application modules; that is not an authenticated external
interface for KeyRecord to a user's current tab. Catalog data, cached definitions,
the app checkout revision and dependency versions cannot stand in for that link.

Real browser/runtime collection and importer build identity remain unimplemented.
This increment establishes repeatable source-selection behavior and prevents
future source work from assuming catalog/VID-PID/readiness equivalence. It does
not establish end-to-end runtime binding or enable VIA generation. A qualified
read-only browser integration or upstream runtime interface remains necessary.
Real device, Keychain restore, uninstall and release validation remain deferred;
deletion review and the empty production support directory remain unchanged.
