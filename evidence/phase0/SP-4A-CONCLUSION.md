# SP-4A Validated Conclusion

Verdict: **PASS**

Evidence: `sp4a/evidence.json` (`11bbbba902d62b2dc510d49720cdef4930dda62397dd797a7e61baa5bb00aec9`)
Manifest: `sp4a/manifest.sha256` (`509d4b21fc9082fc1f20f43da51bb05c2463fd33b7b27762dc9097b90445f3ad`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=4, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4a","--environment","evidence/phase0/environment.json","--output","<output>/sp4a"]
```
