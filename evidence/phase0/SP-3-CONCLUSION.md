# SP-3 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp3/evidence.json` (`9d89409660a26516e3a1aec588fb2c44ec801c63c0ed59528831d9f36a97a6d5`)
Manifest: `sp3/manifest.sha256` (`3834f0c3b3739662d516d6196d3c0e656c6a29966bac461d502cf29a7a8f0fce`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=3, BLOCKED=4, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Schema/version sampling, live reload, and <=2s p95 disable latency remain blocked.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp3","--environment","evidence/phase0/environment.json","--output","<output>/sp3"]
```
