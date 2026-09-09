# SP-1 Validated Conclusion

Verdict: **PASS**

Evidence: `sp1/evidence.json` (`4a8495fb1ce56150b7c72c0af71f6d9ddc9ee88194915b155711433175e1ae99`)
Manifest: `sp1/manifest.sha256` (`1715b2371fa39e6352fd05b8b6e16c3c68b8aef0e5489e191ba08203a8bb6111`)
Runner: `c28035c998381e7de75be8f90e61053c9393295c` / `24d9a79c82255f52313bd4a9c15308acf0afb33e`
Counts: PASS=7, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Selected tap identity is bound to the executed listen-only candidate.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
