# SP-2 Validated Conclusion

Verdict: **PASS**

Evidence: `sp2/evidence.json` (`466931a9f0b83a0a9c2daf61af747b894559d334c2630e942fb6de5262638f9c`)
Manifest: `sp2/manifest.sha256` (`d027998937729862e37db97f9eaf5104b99d02e1424b954dd3eaf6d0a2e6db72`)
Runner: `7b3719edc968ed7318cbcc22ef78a341dc0e5f3d` / `cd47eb21daa84a79560b2e7a11d624b63d6a19dc`
Counts: PASS=11, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live aggregate counters are privacy-safe counts only; no keystream or timestamp is persisted.
- O6 is RESOLVED.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
