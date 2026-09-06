# SP-5B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5b/evidence.json` (`6f730c46c80f39db22c1072356c69809c47ae70652d120a251750707cf9e2011`)
Manifest: `sp5b/manifest.sha256` (`d12c12dedb2ee3ea5120784c94f8f7c6f32b06d1d783ae64e8afbc1881bc21da`)
Runner: `a8d89d633b87b8a52a64cb00d696a3dcd03a3e99` / `58d3c82d3d204a896a2a09f39699e3907b04be91`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Replay and deny-all construction prove no live HID behavior; outbound reports are not literally read-only.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5b","--environment","evidence/phase0/environment.json","--output","<output>/sp5b"]
```
