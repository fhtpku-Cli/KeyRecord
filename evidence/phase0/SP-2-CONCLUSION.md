# SP-2 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp2/evidence.json` (`a5b9b9c06cee3bf2e258eeaab635fc86f5f1df22e6b2676d448c6cb2bf7d437d`)
Manifest: `sp2/manifest.sha256` (`d5ec8acddb1c90872a92ee185452a9e07d90f02979b54bb8093388f15d279175`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=3, BLOCKED=8, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live attribution, Secure Input, sleep/wake, tap-reset, sided recovery, and Fn recovery remain blocked.
- O6 remains OPEN.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
