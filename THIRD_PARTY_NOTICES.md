# Third-party materials

KeyRecord's own code uses [Apache-2.0](LICENSE). This does not change the
licenses of dependencies or historical source evidence.

| Material | Use | License / attribution |
|---|---|---|
| PHC Argon2 reference implementation, revision `f57e61e19229e23c4445b85494dbf7c07de721cb` | Linked password-backup KDF; source unchanged | Apache-2.0 selected from the upstream dual-license offer; [original notice](ThirdParty/Argon2-LICENSE.txt), [project](https://github.com/P-H-C/phc-winner-argon2) |
| Apple macOS frameworks | System APIs; not redistributed | Supplied by the operating system under Apple's terms |
| macOS liblzma | Dynamically linked system decoder; not redistributed | Supplied by macOS; KeyRecord's bounded decoder wrapper is original code |
| VIA app, definitions and reader | File-format/definition research and separate offline test tools | Original upstream notices apply to those materials; no VIA application is included in the product |
| Vial GUI, Vial QMK and QMK | Protocol semantics and separate offline test tools | GPL-licensed upstream applications/firmware are not linked or bundled; their source checkouts retain their own licenses |
| Karabiner-Elements | Separate installed backend and configuration interoperability | Not linked or bundled; [retained upstream license](evidence/phase0/sources/repos/karabiner/license/LICENSE.md) |
| Historical Phase 0 source evidence | Research records only | Each retained project has its original notice under [evidence/phase0/sources/repos](evidence/phase0/sources/repos) |

The SwiftPM dependency declaration is in [Package.swift](Package.swift).
The release app includes `LICENSE`, `NOTICE` and `Argon2-LICENSE.txt` so users
receive the notices with the binary. Research fixtures and external offline
oracle checkouts do not expand the app's dependency or supported-device scope.
