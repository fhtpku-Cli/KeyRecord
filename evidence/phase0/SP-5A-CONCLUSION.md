# SP-5A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5a/evidence.json` (`f498d72018f6f8eb3d9d84a9171b1d36b4b1f2207c53e51c4eba483d6f299b48`)
Manifest: `sp5a/manifest.sha256` (`8095ffdc7d9f6175097dbad02990607af6359976b8b01aaf4c518b2fa7a897f0`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic .vil round-trip proves no official importer or real-device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5a","--environment","evidence/phase0/environment.json","--output","<output>/sp5a"]
```
