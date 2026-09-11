# SP-4B Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp4b/evidence.json` (`cf47dc39cbfd1d077b80de9e7dbff748114bfacef872fd788cbd558cc053eb51`)
Manifest: `sp4b/manifest.sha256` (`8992668c7b2b7236beb09860fd9cfbe4bcbbcb5309b054222e505c5d69df5103`)
Runner: `3df401b8304e7775343a011f1f2fe794be43713e` / `eedebcc9d875b50da4c323411a4e5972dc237959`
Counts: PASS=2, BLOCKED=3, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic layout round-trip proves no official importer, device protocol, firmware keycode, or deployment compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp4b","--environment","evidence/phase0/environment.json","--output","<output>/sp4b"]
```
