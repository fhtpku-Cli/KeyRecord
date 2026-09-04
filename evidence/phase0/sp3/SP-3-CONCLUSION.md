# SP-3 conclusion

Verdict: **BLOCKED**

Fixture-only managed-block and recovery assertions executed. Official schema lint, version sampling, live reload, and disable latency remain BLOCKED when their detectors are false; no user Karabiner file or process was accessed.

- `sp3.atomicity`: PASS (`executed`)
- `sp3.crashRecovery`: PASS (`executed`)
- `sp3.disableLatency`: BLOCKED (`karabiner_or_input_monitoring_unavailable`)
- `sp3.managedBlock`: PASS (`executed`)
- `sp3.reload`: BLOCKED (`karabiner_or_input_monitoring_unavailable`)
- `sp3.schemaLint`: BLOCKED (`supported_karabiner_cli_absent`)
- `sp3.versionSample`: BLOCKED (`supported_karabiner_cli_absent`)
