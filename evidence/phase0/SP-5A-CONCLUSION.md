# SP-5A Validated Conclusion

Verdict: **BLOCKED**

Evidence: `sp5a/evidence.json` (`2247a36277671071f1f467719bc8fe842ab7b7d13dbb7181d934f18ceb226b8d`)
Manifest: `sp5a/manifest.sha256` (`12a38d1186a9d7d5d272c83a20a1a6b6650dd41c599d40831b72acebb1f0d282`)
Runner: `2b4b41457592527688967a19be00fa618b11c845` / `2a5d13185ed6fc231b8afd93bc90ddf0710efc17`
Counts: PASS=3, BLOCKED=1, INCONCLUSIVE=0, FAIL=0
Dependency frozen: `false`

## Limitations
- Synthetic .vil round-trip proves no official importer or real-device compatibility.

## Exact rerun argv
```json
["swift","run","--package-path","Spikes","Phase0Probe","sp5a","--environment","evidence/phase0/environment.json","--output","<output>/sp5a"]
```
