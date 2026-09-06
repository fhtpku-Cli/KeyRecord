# SP-2 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp2/evidence.json` (`c575eec4f9d48d84bc6ac1c341256e23f10cb2baabd03c40061163d3130cc4c6`)
Manifest: `sp2/manifest.sha256` (`f51b1f56e29bce7ffe5623a5f7e13b1f81d87463b64906d5036ccbafdf3b8141`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=3, BLOCKED=8, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live attribution, Secure Input, sleep/wake, tap-reset, sided recovery, and Fn recovery remain blocked.
- O6 remains OPEN.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
