# SP-6A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6a/evidence.json` (`f69000f6b3b40c8c18d8a661ff14d220cf0e8522116cc8d1434e908f42dfcec2`)
Manifest: `sp6a/manifest.sha256` (`27b5a6665f2e4c3846dfa19dfe4310618e112c923d07617bc2e050ece24f0b1c`)
Runner: `4c16b0f961f5f1734ab74f098445292332b0c3a0` / `abb0b1463cd0f4ec6790f53697f075b0dd52df9a`
Counts: PASS=5, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Data-protection Keychain selection and lifecycle remain blocked; no plaintext fallback is permitted.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6a","--environment","evidence/phase0/environment.json","--output","<output>/sp6a"]
```
