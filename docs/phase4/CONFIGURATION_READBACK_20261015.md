# 宏、布局选项与 QMK 设置读回

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

Base: main `a8aeae8e788ccfec84a35f1fcfb8dedbae8e532a`.

## Reproduction and implementation

The encrypted public transaction test retained an original, exported one matrix
change, claimed import, and then changed only the macro, layout options or QMK
settings on its simulated device. Before this increment all four cases remained
`partiallyVerified`: the adapter never queried those three protocols and could
not distinguish matching content from changed content. The red run recorded 16
failed assertions in `/private/tmp/keyrecord-config-readback-red.log`.

The Vial 6 adapter now reads macro count/capacity (`0C`, `0D`) and the active
NUL-terminated macro buffer in up to 28-byte chunks (`0E`). It compares official
UTF-8 text, tap/down/up actions, extended keycodes including zero-low-byte
escaping, and delay encoding. It checks response echoes, complete control
sequences and terminators, then rechecks count/capacity. Unused buffer padding
is not part of the active macros. Unknown actions and unsupported representations
remain opaque. Zero active macros still require count/capacity responses.

Layout options use the independent big-endian 32-bit `02/02` value. The official
`-1` sentinel is verified only when the independently fetched keyboard definition
has no layout labels. Unknown availability does not verify that sentinel; a saved
numeric option conflicting with an optionless definition is a mismatch.

QMK settings use `FE/09` paginated supported-ID enumeration and `FE/0A` reads.
The decoder implements the 1/2/4-byte widths of the 27 known upstream settings.
IDs must advance, terminator padding must be valid, GET status must succeed, and
the supported set is checked again. An unknown device setting leaves the section
unverified rather than guessing its size. Values and supported IDs are compared,
so an empty saved object cannot hide a device's nonempty settings.

Configuration differences produce `externallyChanged` even when the matrix and
encoders match. Matched section names are stored in the existing encrypted
journal and pending evidence operation. Replay preserves coverage; incomplete
observations clear previous coverage; legacy records without coverage stay
partial. Originals remain byte-identical and deletion still requires the
existing recovery review. No new hashes, baselines or release gates were added.

## Official offline oracle and validation

`Scripts/vial-configuration-oracle.py` executes unchanged methods from official
[Vial GUI aef8222](https://github.com/vial-kb/vial-gui/tree/aef8222a2d0429a183b2ed692d5f9efcfd383f08):
macro action restore/serialize, macro GET/reload/save, keyboard layout read,
QMK settings enumeration/read and field codecs. It extracts method ASTs to avoid
GUI/HID initialization, supplies synthetic reports, and records
`evidence/phase4/fixtures/synthetic/vial6-configuration.json`. Swift tests consume
that fixture, including every setting width and a macro control sequence crossing
a report boundary. No official method body is rewritten.

```sh
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-configuration-oracle.py \
  --source /private/tmp/keyrecord-official-vial-gui \
  --output /private/tmp/vial6-configuration.json
swift test --filter 'VialConfiguration|VialReadbackAdapterTests|VialDeviceReadTests|FirmwareOperationTests'
```

Local validation: 781 package tests passed; unsigned arm64 build-for-testing
succeeded; 76 native mapping scenarios and the separate production-composition
scenario passed with injected endpoints. Additional regressions cover malformed
macro controls, absent terminators, bad echoes/status, changing capabilities,
unknown fields/IDs, each new protocol's privacy revocation, encrypted replay and
legacy journals. Native tests exercise empty-buffer evidence, independent absent
layout options, persisted mismatch, and the online-importer explanation.

The existing official roundtrip probe was updated for explicit synthetic empty
settings/dynamic counts and the correct `-1` optionless-definition sentinel. Its
32-layer run exchanged 71 simulated reports, compared 224 matrix and 64 encoder
slots, reopened the encrypted partial result, and restored the patch through
official methods. Its opaque macro/dynamic fixture stubs do not establish real
subprotocol compatibility; the new oracle establishes that separate scope.

Self-review found no remaining blocker: reports are typed GETs only, every report
passes existing cancellation/authorization and length checks, no raw observed
macro or setting content is added to persistent metadata, partial evidence cannot
be promoted by old journal fields, and the production support directory remains
empty. Temporary logs are under `/private/tmp/keyrecord-config-readback-*`.
Push/PR and post-merge main CI are checked separately on their exact commits.

## VIA online importer source

The official [VIA build configuration](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/vite.config.ts)
reads `public/definitions/hash.json`; the corresponding
[HTML template](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/index.html)
publishes it as `definition_hash`. This identifies definition data, not the
importer implementation. A read-only fetch of `https://usevia.app/` on 2026-10-15
found that field and asset filenames, but no importer version/build revision in
the HTML or response headers inspected. This is a bounded source finding, not a
claim that no future upstream source can exist.

Neither a static resource filename nor a source checkout revision proves which
runtime a user's open VIA tab is running. The product therefore keeps importer
identity unknown and now explains that limitation alongside independently read
device versions. No page script was executed and no product network lookup,
invented version endpoint, asset hash contract or compatibility override was added.
Completing this source requires an upstream runtime version tied to the loaded
importer, or a separately qualified packaged importer. VIA definition provenance
also remains outstanding.

## Remaining boundary

This closes the three understood Vial configuration read protocols offline.
Unknown/new representations and unrelated saved fields remain partial. The
multi-report read is not atomic and cannot prove coherence if another editor
changes values without changing identity/counts; real qualification requires a
quiet device. UTF-8 comparison follows official restore serialization and does
not claim the upstream GUI's Unicode save/restore cycle is lossless.

No real HID enumeration/open/send, live capture, real Keychain restore, uninstall,
signing, notarization or public release validation occurred. Those activities
remain deferred. Offline protocol tests, native simulated execution and CI do not
establish G3/G4 or device/version qualification.
