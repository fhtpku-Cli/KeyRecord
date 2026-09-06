# SP-4B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp4b/evidence.json` (`0077b9c6a7cc46a27105ea78b4065d79b1096b739bd92c5307136a44298d25b5`)
Manifest: `sp4b/manifest.sha256` (`962ced379926def1091bd9905a833b259c7fcf8c263f8fde5c4c28e1f00fcda1`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=2, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4b","--environment","evidence/phase0/environment.json","--output","<output>/sp4b"]
```
