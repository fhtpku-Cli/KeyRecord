# SP-4B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp4b/evidence.json` (`89a84377ccd9e8038a4faea9ad659c8096bfcb4de649f3c01ea0c151d092b5c2`)
Manifest: `sp4b/manifest.sha256` (`bab07f7548e7f6c88375dd1aa3f614c450ca5a5e2a21f91572f0a74294a7d9e9`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=2, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4b","--environment","evidence/phase0/environment.json","--output","<output>/sp4b"]
```
