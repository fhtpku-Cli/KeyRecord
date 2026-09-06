# SP-4A Validated Conclusion

Verdict: **PASS**

Evidence: `sp4a/evidence.json` (`eb0393d6f82f5b451d896a23f1572363269dd23161992570b503d02965422b38`)
Manifest: `sp4a/manifest.sha256` (`89fd63608aa674db46f284c9f2d1973a68fc2a044b65bfc3e3571c7250ad1260`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=4, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- PASS covers V2/V3 definition schema parsing only; it proves no protocol, keycode, importer, or device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4a","--environment","evidence/phase0/environment.json","--output","<output>/sp4a"]
```
