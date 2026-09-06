# SP-4B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp4b/evidence.json` (`25c99a50fec9bb64ac418b00178b34d3dc19c97854176e70e239b02e219ec040`)
Manifest: `sp4b/manifest.sha256` (`1d9500496a452ca6102504b33343b6276218a2e0bff04f71ead9ed3e07639c30`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=2, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4b","--environment","evidence/phase0/environment.json","--output","<output>/sp4b"]
```
