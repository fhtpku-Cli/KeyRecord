# SP-5B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5b/evidence.json` (`be7cd0900d91490d1499b27f67b98b28febebe7e851d154d86cc33018cbadf8f`)
Manifest: `sp5b/manifest.sha256` (`9094e2c0892b9682ff3ac31f27ff230408e1bdfbc942ec3197b091156304f1cb`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5b","--environment","evidence/phase0/environment.json","--output","<output>/sp5b"]
```
