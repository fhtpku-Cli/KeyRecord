# SP-5B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5b/evidence.json` (`cbe38ef2d3f8ac5ed3dbe280cc4ecf3f253485d6f1135995a5b43dd9afd9c8af`)
Manifest: `sp5b/manifest.sha256` (`35189027225dee618d7ca2c1c969afc4aeccdaf21b79d2c35a26acd5cb5230e2`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5b","--environment","evidence/phase0/environment.json","--output","<output>/sp5b"]
```
