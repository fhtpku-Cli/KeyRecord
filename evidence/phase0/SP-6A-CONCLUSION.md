# SP-6A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp6a/evidence.json` (`c7eb36bd3ed738c82bddbcd5c86cfbda3907ec53f416b8a27b86ecc8f0659410`)
Manifest: `sp6a/manifest.sha256` (`3a5f92c91f770d32202ce06d97ebf5c6123463c3f0e88a416990a472743e27e9`)
Runner: `7b3719edc968ed7318cbcc22ef78a341dc0e5f3d` / `cd47eb21daa84a79560b2e7a11d624b63d6a19dc`
Counts: PASS=5, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Data-protection Keychain selection and lifecycle remain blocked; no plaintext fallback is permitted.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp6a","--environment","evidence/phase0/environment.json","--output","<output>/sp6a"]
```
