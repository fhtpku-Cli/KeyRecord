# 动态条目读回与 VIA 独立设备版本

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `59bb5da453c9c8245256584441ec3c7245a1e7fb`.

## Reproduction and result

The public encrypted transaction regression changed each of four dynamic tables
while keeping the expected matrix unchanged. Before this change the reader sent
zero dynamic requests and returned `partiallyVerified` for every case, without
detecting any changed entry. The red run recorded ten failed assertions in
`/private/tmp/keyrecord-subprotocol-red.log`.

The Vial 6 reader now implements the four dynamic-entry GET subprotocols:
Tap Dance, Combo, Key Override and Alternate Repeat Key. It reads device counts,
then every entry in each understood section, and checks the counts again before
the existing final identity/layer checks. Only the typed count/GET commands are
constructible; no dynamic setter, unlock or reset was added. Entry status, report
length, authorization, cancellation and transport failures prevent an observation.

Comparison uses the official little-endian field layouts and the existing bounded
keycode dialect. A changed table or count produces `externallyChanged`, even with
matching matrix/encoders. Empty tables require actual zero device counts. Missing
observations, malformed sections, unknown names, unknown fields and reserved
options do not gain coverage. Supported GET results do not authorize editing a
dynamic action or overwriting a protected layer entry.

Successfully compared section names are recorded in the existing encrypted
journal and pending transaction. Interrupted evidence replay retains this scope;
another incomplete readback removes its old coverage. Legacy records have no new
coverage and remain partial. Original recovery bytes and deletion review remain.
No hash, frozen contract, baseline or additional release gate was introduced.

## Official protocol evidence

`Scripts/vial-dynamic-oracle.py` executes the unchanged official count, GET, reload
and save method bodies against synthetic reports. Its generated fixture is used
by the Swift codec test, independently of the public transaction mutation test.
This exercises the subprotocols themselves, rather than the former top-level
save/restore recorder. Sources:

- [Vial base protocol](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/base_protocol.py)
- [Dynamic entry counts](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/dynamic.py)
- [Key override codec](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/key_override.py)
- [Alternate repeat codec](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/alt_repeat_key.py)

## VIA source and product integration

The new explicit “Retain VIA copy and read device versions” action selects a HID
interface whose VID/PID matches the imported copy, then reads the selected device.
It rechecks authority after the modal picker and before/after every report, closes
the connection on completion/error/clear, and retains the observed facts inside
the encrypted original-copy record. The UI displays the protocol and keycode
version, including an explicit unknown keycode version for older protocols.

The source recognizes VIA protocols 7 through 13. Protocols below 13 supply only
their protocol number; they are never sent a newer keycode-version query. Protocol
13 supplies the four big-endian BCD keycode-version bytes, currently recognizing
versions 8 and 9. Echo, length, malformed/unsupported versions and a changed final
version are rejected. This follows the official [VIA load condition](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/store/firmwareSlice.ts)
and [keycode-version decoder](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/utils/keycodes-version.ts).

Definition schema and importer identity remain unknown. In particular, the
[official VIA desktop wrapper](https://github.com/the-via/releases/blob/abeed97/README.md)
loads the online application: its bundle version cannot identify the loaded
importer code. The source therefore does not substitute a desktop-wrapper version,
browser version, source checkout revision or imported file claim for that fact.
Observed versions alone cannot qualify a device or enable patch generation.
The production support directory remains empty. Explicit VIA version inspection
is read-only and does not bypass the existing qualified Vial readback path.

## Remaining scope and validation boundary

Macro buffers, layout options and QMK settings are separate protocols and remain
unverified, as do unsupported/unknown dynamic representations. Consequently a
normal complete Vial save containing those sections still reports partial
verification. The four dynamic-entry GET protocols are implemented; this does
not claim every saved setting is verified or complete Phase 4 qualification.

Multi-report HID reads are not atomic. The identity/topology/version rechecks can
detect changes they observe, but cannot prove a coherent snapshot if firmware or
another editor changes same-device values mid-read. Real validation needs a quiet
device/configuration. No real HID device, live capture, real Keychain restoration,
uninstall, signing, notarization or release validation was executed in this round.

Offline validation includes the official oracle, public transaction mismatch and
encrypted replay tests, malformed/changed/error reports, native empty-table
readback and VIA picker revocation, the package suite and unsigned App builds.
CI and native synthetic execution are separate evidence layers.

Local results: 771 package tests passed; the final focused run passed all seven
dynamic/VIA version tests after the evidence-replay assertions were added.
The unsigned arm64 build-for-testing succeeded. All 75 native mapping scenarios
and the separate production-composition scenario passed. Logs are under
`/private/tmp/keyrecord-subprotocol-*`; temporary logs are not durable release
evidence. PR/push and post-merge main CI must still be checked on their exact SHAs.
