# SP-2 conclusion

Verdict: **BLOCKED**

O6: **OPEN**

G0: **OPEN**

Live checks were bounded metadata preflights only. No permission prompt, sleep, persistent monitor, event detail, key, text, sequence, or exact timestamp was recorded.

- `sp2.excludedApp`: BLOCKED (`input_monitoring_denied`)
- `sp2.fnRecoveryLive`: BLOCKED (`input_monitoring_denied`)
- `sp2.fnRecoveryModel`: PASS (`executed`)
- `sp2.frontmostIndeterminate`: PASS (`executed`)
- `sp2.frontmostKnown`: BLOCKED (`input_monitoring_denied`)
- `sp2.frontmostUnattributable`: BLOCKED (`input_monitoring_denied`)
- `sp2.secureInput`: BLOCKED (`secure_input_helper_unavailable`)
- `sp2.sidedModifiers`: PASS (`executed`)
- `sp2.sidedRecovery`: BLOCKED (`input_monitoring_denied`)
- `sp2.sleepWake`: BLOCKED (`noninteractive_sleep_privilege_unavailable`)
- `sp2.tapReset`: BLOCKED (`input_monitoring_denied`)
