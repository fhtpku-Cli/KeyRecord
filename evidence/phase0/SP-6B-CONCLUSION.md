# SP-6B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6b/evidence.json` (`20d9fe1f9f208083794cc52bdf4d3839e87c81bb28119fb1de258d9ef7b28dd2`)
Manifest: `sp6b/manifest.sha256` (`3a643df8e3970ecb015a3201775b39a3a1d595b364984f280e7768e378d4b689`)
Runner: `b19a3436606a2cbafadf38140d96824dac39f2ec` / `97b003dda9d6519b74f7402585b765b84d051093`
Counts: PASS=6, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Intel timing remains blocked and the production dependency/API is not frozen.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6b","--environment","evidence/phase0/environment.json","--output","<output>/sp6b"]
```
