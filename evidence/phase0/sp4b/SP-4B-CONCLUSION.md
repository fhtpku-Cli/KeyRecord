# SP-4B conclusion

Verdict: **BLOCKED**

The exact deterministic synthetic `.layout.json` fixture proves only bounded parsing and one selected-slot raw splice with every non-selected byte and opaque macro/encoder subtree preserved. It is synthetic, not sourced, pinned, or live. The layout artifact is not claimed as a stable interchange standard and no deployment was exported.

Five independent axes are recorded with evidence XOR a complete blocker: definition schema PASS from SP-4A evidence; layout format PASS from the exact synthetic fixture; device protocol, firmware-selected keycode dialect, and official importer compatibility BLOCKED. Protocol and keycode dictionaries are firmware-dependent. VIA protocol 13 is not Vial-GUI compatible.

Official VIA import and device behavior remain **BLOCKED** because the exact environment inventory reports VIA absent and no approved VIA device. No GUI was launched and no HID/device access or write occurred.
