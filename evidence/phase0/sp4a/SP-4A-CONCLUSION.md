# SP-4A conclusion

Verdict: **PASS**

This definition-only fixture result identifies the pinned VIA V2 and V3 definition schemas. It proves bounded parsing and byte-identical preservation outside the selected `name` scalar, including opaque unknown and macro subtrees. It makes no device-protocol, keycode-dialect, layout-backup, official-importer, HID, EEPROM, or device-behavior claim.

Official definitions are repository-served; manufacturer-provided custom definitions use VIA's Design tab, as stated by the pinned sources below.

- `sp4a.bounds`: PASS (`bounds.json`)
- `sp4a.opaqueRoundTrip`: PASS (`opaque-preservation.json`)
- `sp4a.v2Schema`: PASS (`v2-schema.json`)
- `sp4a.v3Schema`: PASS (`v3-schema.json`)

## Source citations

- `evidence/phase0/sources/repos/via-docs/files/docs/specification.md` SHA-256 `0b6644085eac41dd0f3b30a2573e38266c9cf8f365ef0091b3998f5de5b4c4ca`
- `evidence/phase0/sources/repos/via-docs/files/docs/post_v3_changes.md` SHA-256 `cd8adb7a3a9c5422154667304da0eb39c95ad1417772f50f392168a4f04efc2a`
