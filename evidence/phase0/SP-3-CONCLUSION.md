# SP-3 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp3/evidence.json` (`65b6c8d2ae40c4edff39b745e2420ef92feda1fe1c04d6d6936c9bad1ca56eca`)
Manifest: `sp3/manifest.sha256` (`d782303b64651ca6108ebc4e5ecd046f81dc21ee02fe9af1c16fddf6cd7f7052`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=3, BLOCKED=4, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp3","--environment","evidence/phase0/environment.json","--output","<output>/sp3"]
```
