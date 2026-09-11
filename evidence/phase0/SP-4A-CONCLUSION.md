# SP-4A Validated Conclusion

Verdict: **PASS**

Evidence: `sp4a/evidence.json` (`ffcc5b83b80946770e148a53513d4390422dc7d4b97c4cb68c8f9258382d64bf`)
Manifest: `sp4a/manifest.sha256` (`6677e7d67d3934208741bcea02280d9691a5a3af5676aa5576248dec19230386`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=4, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4a","--environment","evidence/phase0/environment.json","--output","<output>/sp4a"]
```
