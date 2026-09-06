# SP-4A Validated Conclusion

Verdict: **PASS**

Evidence: `sp4a/evidence.json` (`cda471a95ef5cbaeb77abaacf63b9f6ca9d0a36ab8e835e257252c4ab67b4991`)
Manifest: `sp4a/manifest.sha256` (`910e35d4c9e757e88604dfa6f8755b47e7af187c0e543dc1f0694864abbb9833`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=4, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4a","--environment","evidence/phase0/environment.json","--output","<output>/sp4a"]
```
