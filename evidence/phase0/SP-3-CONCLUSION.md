# SP-3 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp3/evidence.json` (`c09633fd58508a7fb114b04f75088fb35d57da2b674838d09037dfd4a2f49b39`)
Manifest: `sp3/manifest.sha256` (`c335a7bf9b47491f4e55979ec061d5527ae80eb6ea9c88c4259a498e83996081`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=4, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp3","--environment","evidence/phase0/environment.json","--output","<output>/sp3"]
```
