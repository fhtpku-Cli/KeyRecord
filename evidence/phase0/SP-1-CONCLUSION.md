# SP-1 Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp1/evidence.json` (`f4a067f269f2ed183f32745adb40e3b80210c72fd4e5dbf5ba22060c4dff7966`)
Manifest: `sp1/manifest.sha256` (`449e0c775f62aee8dd51b1d7345ba37f59b904793fa5c993e412e25c063376d7`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=0, BLOCKED=7, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Input Monitoring and Karabiner were unavailable; no tap candidate is selected.
- O7 excludes only product-stamped synthetic events and otherwise fails closed.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp1","--environment","evidence/phase0/environment.json","--output","<output>/sp1"]
```
