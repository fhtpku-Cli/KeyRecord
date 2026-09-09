# SP-6A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6a/evidence.json` (`b3fe3295f60af357b978ff5614c12516e5b54ca46824e208e0024f34b5b5d157`)
Manifest: `sp6a/manifest.sha256` (`401f64fccc0405986af3190c1fad8b0098ef35418f7915de9f9495f9a35a5ee5`)
Runner: `4c16b0f961f5f1734ab74f098445292332b0c3a0` / `abb0b1463cd0f4ec6790f53697f075b0dd52df9a`
Counts: PASS=5, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Data-protection Keychain selection and lifecycle remain blocked; no plaintext fallback is permitted.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6a","--environment","evidence/phase0/environment.json","--output","<output>/sp6a"]
```
