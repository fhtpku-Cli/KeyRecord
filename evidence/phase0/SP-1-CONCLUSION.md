# SP-1 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp1/evidence.json` (`2e3cb4a5673b3a78f09dc8e63f45ab5f0960ba896bf7702133d64f911f97696b`)
Manifest: `sp1/manifest.sha256` (`bc38ba3320f597a7f06bc88ba57269f6929fdb4cb6d7fb13c583932e124251ec`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=0, BLOCKED=7, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Input Monitoring and Karabiner were unavailable; no tap candidate is selected.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
