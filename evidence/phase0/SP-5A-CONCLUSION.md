# SP-5A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5a/evidence.json` (`001a947ff13edb6835e7875aeb259c141009c58f99dc00722c2866196a14404a`)
Manifest: `sp5a/manifest.sha256` (`64bc85177ecdceeeff12995fceb01f47e2886be24c22e08a01d71f7f64eb7e34`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic .vil round-trip proves no official importer or real-device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5a","--environment","evidence/phase0/environment.json","--output","<output>/sp5a"]
```
