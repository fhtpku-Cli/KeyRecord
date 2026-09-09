# SP-2 conclusion

Verdict: **BLOCKED**

O6: **OPEN**

G0: **OPEN**

Live checks were bounded metadata preflights only. No permission prompt, sleep, persistent monitor, event detail, key, text, sequence, or exact timestamp was recorded.

- `sp2.excludedApp`: PASS (`executed`)
- `sp2.fnRecoveryLive`: PASS (`executed`)
- `sp2.fnRecoveryModel`: PASS (`executed`)
- `sp2.frontmostIndeterminate`: PASS (`executed`)
- `sp2.frontmostKnown`: PASS (`executed`)
- `sp2.frontmostUnattributable`: PASS (`executed`)
- `sp2.secureInput`: PASS (`executed`)
- `sp2.sidedModifiers`: PASS (`executed`)
- `sp2.sidedRecovery`: PASS (`executed`)
- `sp2.sleepWake`: BLOCKED (`noninteractive_sleep_privilege_unavailable`)
- `sp2.tapReset`: PASS (`executed`)
