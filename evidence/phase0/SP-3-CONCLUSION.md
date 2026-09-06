# SP-3 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp3/evidence.json` (`080d374a1532f75fda0484168805b16f5d1a2d58cb26fc1bbe7afb154e341251`)
Manifest: `sp3/manifest.sha256` (`86b5446100565919de0bf56ba414e13c0e52e9084a91c594b6bda17def979cb9`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=3, BLOCKED=4, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp3","--environment","evidence/phase0/environment.json","--output","<output>/sp3"]
```
