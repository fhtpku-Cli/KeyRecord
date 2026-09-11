# SP-1 Validated Conclusion

Verdict: **PASS**

Evidence: `sp1/evidence.json` (`b4eb8b68813ccdff07a08453d6c083a39a01a47af96c9122e7e06d6cefc478cd`)
Manifest: `sp1/manifest.sha256` (`bd075b237c56add2efd1eda85cb80458ee03533ce9946870718419c334203847`)
Runner: `7b3719edc968ed7318cbcc22ef78a341dc0e5f3d` / `cd47eb21daa84a79560b2e7a11d624b63d6a19dc`
Counts: PASS=7, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Selected tap identity is bound to the executed listen-only candidate.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
