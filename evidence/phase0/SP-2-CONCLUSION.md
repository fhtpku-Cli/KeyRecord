# SP-2 Validated Conclusion

Verdict: **PASS**

Evidence: `sp2/evidence.json` (`f48916c05057a3b4284591de5b16c3d54594242b7830f4cbe1f4db79942a0792`)
Manifest: `sp2/manifest.sha256` (`d6feed685d96c1ef78260be44d99452dff1c003a47934a9446ad6951c1c7a4f7`)
Runner: `be9e2d363bdd83148ead5f0fbe3ef5437bfefa11` / `96dafb924985890ac17fc818f23e7302c63d9716`
Counts: PASS=11, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live aggregate counters are privacy-safe counts only; no keystream or timestamp is persisted.
- O6 is RESOLVED.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
