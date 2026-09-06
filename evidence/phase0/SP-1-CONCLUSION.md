# SP-1 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp1/evidence.json` (`92a0c7e24423ce0e77a3bfecc052086d2faf87a10307c523fd1ae64e1aac0f48`)
Manifest: `sp1/manifest.sha256` (`2ae2ca634e92398d958bdabe1aec725fd818a8cf92f3d45c7b7ce5632414baa5`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=0, BLOCKED=7, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Input Monitoring and Karabiner were unavailable; no tap candidate is selected.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
