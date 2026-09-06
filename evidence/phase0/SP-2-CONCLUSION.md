# SP-2 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp2/evidence.json` (`df8471bed9a25f2455a5e304380f32ee676fb3fd01ad95bf1640cc22e8c68f9b`)
Manifest: `sp2/manifest.sha256` (`1de3786c54fa6fe93eda12af7c2c4852e365838ca19ebb10ca8c00f9caf45846`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=3, BLOCKED=8, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Live attribution, Secure Input, sleep/wake, tap-reset, sided recovery, and Fn recovery remain blocked.
- O6 remains OPEN.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp2","--environment","evidence/phase0/environment.json","--output","<output>/sp2"]
```
