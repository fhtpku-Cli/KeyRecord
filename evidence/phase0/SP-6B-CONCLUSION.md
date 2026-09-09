# SP-6B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6b/evidence.json` (`206e95da94e641d1e8dd6d92f9153fbdfa16c48826f9439d7ef12ad656958068`)
Manifest: `sp6b/manifest.sha256` (`a35f7842b43fd34ea9b384b2876207dfd438ea5a4a3adf052614b1b17655091f`)
Runner: `b19a3436606a2cbafadf38140d96824dac39f2ec` / `97b003dda9d6519b74f7402585b765b84d051093`
Counts: PASS=6, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Intel timing remains blocked and the production dependency/API is not frozen.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6b","--environment","evidence/phase0/environment.json","--output","<output>/sp6b"]
```
