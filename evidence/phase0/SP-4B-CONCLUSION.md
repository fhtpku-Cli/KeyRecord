# SP-4B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp4b/evidence.json` (`718a20afa6fec1f4b5a6d158db40237b33d7c9acea444c7e36dad52da0ec698a`)
Manifest: `sp4b/manifest.sha256` (`4573f2890a2e2bfbea091c4cbd6d2fca5253ebbe505c92dff77b7998ab439d0f`)
Runner: `9b24cfbd8537fa8408e734a1d84f085038dd12b8` / `3a198377fdadf0fadd34f6f8878ead6e11ccc02b`
Counts: PASS=2, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4b","--environment","evidence/phase0/environment.json","--output","<output>/sp4b"]
```
