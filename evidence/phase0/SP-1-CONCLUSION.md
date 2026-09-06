# SP-1 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp1/evidence.json` (`f4fd30f1ffeeae69dd0f01dc2ba73afd442ad476baf5fe9766d837f29b140c4e`)
Manifest: `sp1/manifest.sha256` (`e5a53e3848b10eca5b5b5cda396adec00d51295fbffffa41542b6fb7a4cc47dd`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=0, BLOCKED=7, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Input Monitoring and Karabiner were unavailable; no tap candidate is selected.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
