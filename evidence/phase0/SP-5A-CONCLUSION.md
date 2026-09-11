# SP-5A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5a/evidence.json` (`59a5ab690be869db3a81cce28832be1ad3c28b016b22275cefee8b287acd1829`)
Manifest: `sp5a/manifest.sha256` (`5443543a6c590c8fe84b3a15e56fcb847914fc90d7d8191074a62522d4689041`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic .vil round-trip proves no official importer or real-device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5a","--environment","evidence/phase0/environment.json","--output","<output>/sp5a"]
```
