# SP-5B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5b/evidence.json` (`43c70908602eab65fdff1033366884fa988a5ca42225148933dd3e2cb4f14756`)
Manifest: `sp5b/manifest.sha256` (`db3133a58e6ebaccc04c8b9006d546f885d2db0ba247a25b9b66a4d9d135c71b`)
Runner: `a5bb0fdac50be69d7abdbe2456c610f3e3e795a7` / `50abaf6d0af37bee489130dbc6a3668bcb40f053`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5b","--environment","evidence/phase0/environment.json","--output","<output>/sp5b"]
```
