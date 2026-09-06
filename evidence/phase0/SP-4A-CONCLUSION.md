# SP-4A Validated Conclusion

Verdict: **PASS**

Evidence: `sp4a/evidence.json` (`643ca5b1e7e625fd73462294fb369599a923cabb8ab58658f52ccf74dc3ac5b2`)
Manifest: `sp4a/manifest.sha256` (`86922de63b7be72df1860f11c047f680b6a5b3f0f3519685c7acfabf406c2af3`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=4, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4a","--environment","evidence/phase0/environment.json","--output","<output>/sp4a"]
```
