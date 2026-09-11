# SP-6B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6b/evidence.json` (`4791df37581c02949c9c1fdea08f06400e3011ce7d0769e8df9dc6c3cc8feb14`)
Manifest: `sp6b/manifest.sha256` (`d7f44a2216cac0651712ee252b39428a1088d24ad8f6390ed6abd75d1a63686c`)
Runner: `e4f7c383481ff402329a1c2e3bfe5fc14fcbe2e4` / `2b5c66212d6e4205cdb270ba1726e1e529316a1e`
Counts: PASS=6, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Intel timing remains blocked and the production dependency/API is not frozen.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6b","--environment","evidence/phase0/environment.json","--output","<output>/sp6b"]
```
