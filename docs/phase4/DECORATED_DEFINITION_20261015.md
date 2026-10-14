# Vial decorated definition topology

This offline increment starts from main `44fb07d0e90eb90f66efc35d3a9da4e9a90ddffb`.
The old parser rejected valid definitions containing decals, centered legends or leading
KLE metadata. Twelve of thirteen initial upstream-generated cases failed, and the complete
readback connection rejected the decorated definition before reading the keymap.

The parser now preserves alignment across keys and rows, resets the decal flag after one
key, accepts leading metadata and projects normalized matrix/encoder labels. Alignment
values 0 through 7 are recognized; only 0/4 provide the normalized coordinate label.
Centered display text is never mistaken for a matrix coordinate. Encoder markers retain
priority over the decal flag. Alternate-layout occurrences of a coordinate remain a set.

Upstream places a decal without a coordinate at matrix (0,0), includes it in `rowcol`,
and saves that position. KeyRecord therefore includes it in the independent topology
instead of skipping it. The complete file/device comparison still checks it. A file
omitting that position is rejected before matrix or encoder queries.

Invalid alignment/decal types, out-of-range positions, ambiguous encoder coordinates,
misplaced metadata and more than twelve labels are rejected. Existing identity, version,
privacy, occupied-position and full matrix/encoder checks remain. This is topology
interpretation, not full KLE rendering or qualification of dynamic firmware features.

## Independent source and reproduction

`Scripts/vial-official-definition.py` loads the upstream KLE module and executes the
unmodified `reload_layout` method via its sideload path. Protocol checks are inert fixture
methods; no GUI or HID modules are imported. It generates 14 synthetic definitions,
compressed packets and expected matrix/encoder sets, including state persistence/reset,
all alignments, explicit decal cancellation, encoder priority, layout variants and metadata.

Sources are the official [KLE parser](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/kle_serial.py)
and [layout/keymap implementation](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/keyboard_comm.py).

```sh
python3 Scripts/vial-official-definition.py \
  --source /private/tmp/keyrecord-official-vial-gui \
  --output evidence/phase4/fixtures/synthetic/vial6-definition-topology.json
```

## Validation and boundaries

- Before fix: 12 topology fixture failures and one full connection failure, recorded in
  `/private/tmp/keyrecord-definition-build-red.log`.
- After fix: 83 related package tests pass (21 device, 32 readback, 21 firmware operation,
  3 privacy egress, 6 product boundary), `/private/tmp/keyrecord-definition-core.log`.
- Native test build and 70 mapping workflow tests pass, including decorated-definition
  success and encoder mismatch persisted through the encrypted ledger;
  `/private/tmp/keyrecord-definition-native-build.log` and
  `/private/tmp/keyrecord-definition-native.log`.
- Self-review covers label normalization, state lifetime, malformed input, independent
  expectations, bounded decoding and connection closure. No unresolved blocking finding.

All device reports, keys, stores and configurations are synthetic or temporary. Production
support remains empty. Real devices, real Keychain restore, real uninstall and G3/G4
qualification remain deferred. Deletion still requires the existing recovery-copy review.
No new hash, frozen contract, baseline or gate is introduced. Final-head PR/push CI and
post-merge main CI are verified separately from these local results.
