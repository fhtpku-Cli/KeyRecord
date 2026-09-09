# SP-1 Validated Conclusion

Verdict: **PASS**

Evidence: `sp1/evidence.json` (`424b8a245771b024e69e7a6409df9e30cca624cd8d09b0a4bf4fc91ea208de38`)
Manifest: `sp1/manifest.sha256` (`613e08d18e219b5f97d1048e842af6fef6002dc43f87826bde05aa352f39eba6`)
Runner: `3df401b8304e7775343a011f1f2fe794be43713e` / `eedebcc9d875b50da4c323411a4e5972dc237959`
Counts: PASS=7, BLOCKED=0, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Selected tap identity is bound to the executed listen-only candidate.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
