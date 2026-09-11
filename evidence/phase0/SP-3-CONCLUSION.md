# SP-3 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp3/evidence.json` (`f2614b67b7960dd4db909e9f145a5be1a4229463a5b82eaee2161c554edba0e4`)
Manifest: `sp3/manifest.sha256` (`e26fbac7e4b26239b79f877988e5c8c7e8b54df41086c4ffe75363ea6ff87c32`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=4, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp3","--environment","evidence/phase0/environment.json","--output","<output>/sp3"]
```
