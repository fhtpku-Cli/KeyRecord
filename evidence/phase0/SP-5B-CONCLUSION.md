# SP-5B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5b/evidence.json` (`8ee23bf01eb25e640a6d33d5d28a20fac09d0c5bbdb3aca4f71c004302e0b112`)
Manifest: `sp5b/manifest.sha256` (`5f9506dc1d0569144c09a59ce25586b253f76d3113b75d655d48d108c49a9766`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5b","--environment","evidence/phase0/environment.json","--output","<output>/sp5b"]
```
