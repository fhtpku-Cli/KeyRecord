# SP-2 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp2/evidence.json` (`50c7852c4ad26f0fae2ed3769a309fe4a6e08f8536f9fbbebb0376b5241d2f04`)
Manifest: `sp2/manifest.sha256` (`9e31ae97e9796b6e2c2e7cd43eb62c8bad972964b8d0ec0575b6d7e2adfda83a`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=8, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live attribution, Secure Input, sleep/wake, tap-reset, sided recovery, and Fn recovery remain blocked.
- O6 remains OPEN.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
