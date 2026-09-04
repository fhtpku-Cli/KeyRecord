# SP-5A conclusion

Verdict: **BLOCKED**

The exact deterministic synthetic `.vil` fixture proves only bounded version-1 parsing, one selected layout-slot raw splice, byte-identical preservation everywhere else including unsupported advanced fields, and UID mismatch rejection. It is synthetic, not sourced or live, and does not prove official-importer, device-compatibility, HID, firmware, or real-device behavior.

Official Vial GUI import remains **BLOCKED** because D7 is false: the recorded environment inventory reports Vial absent. No GUI was launched and no device or HID interaction occurred.

`vial.json` is a firmware-embedded keyboard definition consumed by the Vial QMK definition generator. It is not interchangeable with a `.vil` keymap export or a VIA definition.

- `sp5a.bounds`: PASS (`bounds.json`)
- `sp5a.importer`: BLOCKED (`vial_gui_absent`)
- `sp5a.uidBinding`: PASS (`uid-binding.json`)
- `sp5a.vilRoundTrip`: PASS (`round-trip.json`)

## Pinned source citations

- `evidence/phase0/sources/repos/vial-gui/files/src/main/python/protocol/keyboard_comm.py` SHA-256 `d71b73a6217c5d12a05ff0cd3c85ea06b8f9df798cfb5f1a783207af4623ecdb`
- `evidence/phase0/sources/repos/vial-gui/files/src/main/python/editor/keymap_editor.py` SHA-256 `5266420876959c83bf4f2d7c5db177170a67a368e028f6b0813b3d1e9e6e03e1`
- `evidence/phase0/sources/repos/vial-qmk/files/util/vial_generate_definition.py` SHA-256 `ecd4b1ffeae61a1918ef704eff47f67e2f55ec48944a34a357af6a48abd4caae`
- `evidence/phase0/sources/repos/vial-qmk/files/keyboards/vial_example/vial_rp2040/keymaps/vial/vial.json` SHA-256 `09bdbe2ced2496af1ac7f0e7bf20956acc76b861670afe890b62f53bf512f711`
