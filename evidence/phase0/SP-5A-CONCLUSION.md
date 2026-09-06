# SP-5A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5a/evidence.json` (`a1bd67a19b55a525fb4a6c42ee95840ab347ad5fef64e0fcd495327deb8b73a9`)
Manifest: `sp5a/manifest.sha256` (`f1be4058e81bff1cdd2f4eb1902d4953ccd798802efce78ba20547a054e4d629`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic .vil round-trip proves no official importer or real-device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5a","--environment","evidence/phase0/environment.json","--output","<output>/sp5a"]
```
