# Firmware offline regression automation

Base: main `bd274e5379d86aedf0dba9e78c081309635b9eb6`.

## Reproduced gaps

The macOS workflow invoked `verify-local.sh --build-only`, which compiled App
XCTest without executing it. The official protocol scripts were only run manually
and needed a separately prepared `simpleeval` source path. Running the dynamic
oracle without that path reproduced `ModuleNotFoundError: simpleeval`.

An actual XCTest invocation with a nonexistent suite also returned exit status 0
after reporting zero executed tests. A stale selector could therefore silently
remove native regression coverage even after adding an XCTest command.

## Execution added

- CI checks out the same official Vial, VIA and Vial-selected simpleeval Git
  revisions used by the existing offline evidence, and installs reader 1.14.4
  without package lifecycle scripts. Python 3.13 runs the unchanged old simpleeval
  dependency; CI's default Python 3.14 reproduced its removed `ast.Num` failure.
  Dependency download is separate from offline
  protocol execution; no network capability is added to the product.
- `verify-firmware-oracles.py` executes the existing official-method scripts and
  compares all 11 generated fixtures with the existing Swift test inputs. JSON
  comparison ignores formatting; XZ topology cases compare decompressed bytes so
  compressor container differences cannot be confused with definition changes.
- Nine keycode families each execute official export, the real Swift encrypted
  retain/export/readback/reopen transaction using simulated reports, and official
  restore/save/reload. Dynamic, macro, layout and QMK setting oracles run separately
  because the older roundtrip probe's opaque stubs cannot prove those protocols.
- `verify-local.sh --firmware-app-tests` retains all package tests, the capture
  harness, Swift Release build and unsigned universal Release/native Debug builds,
  then executes the two offline native suites and production-composition test.
  The default full App suite and explicit build-only mode remain available.
- Each native selector runs in a clean environment. Process failure propagates,
  and an actual nonzero passing test count is required for each selector; no test
  count is frozen. Existing simulated deletion/recovery confirmations remain
  tested. CI retains per-command logs and synthetic native QA artifacts.

These are ordinary executable regressions using existing fixtures and Git
dependency revisions. No new compatibility hash, frozen contract, baseline,
support entry or release gate is introduced.

## Reproduce locally

```sh
python3 Scripts/verify-firmware-oracles.py \
  --vial-source /path/to/vial-gui \
  --simpleeval-source /path/to/simpleeval \
  --via-source /path/to/via-app \
  --reader /path/to/node_modules/@the-via/reader \
  --via-store-dependencies /path/to/node_modules \
  --output /tmp/keyrecord-firmware-oracles
bash Scripts/verify-local.sh --firmware-app-tests
```

The workflow records the dependency revisions. The simpleeval checkout is used
directly, avoiding its old packaging script and any system Python installation.
The subsequent [active-source increment](VIA_ACTIVE_SOURCE_SELECTION_20261015.md)
adds the official VIA store selector scenarios and their Redux/TypeScript dependencies.
Local oracle execution passed all 11 fixture comparisons and nine transaction
round trips. The full revised local entry point passed all 785 package tests,
the capture harness, Release package/universal App builds, native Debug test build
and 90 native tests (78 mapping, 11 import, one production composition).
Injected fixture disagreement and a missing native selector both
returned failure; the latter reproduced XCTest's misleading zero-test success
before exercising the wrapper. Native and full-build results are checked before
the PR is merged, followed by the exact merge's main CI.

## Remaining scope

These runs use synthetic files, in-memory keys, temporary encrypted stores and
injected endpoints. They do not enumerate/open/send to real HID devices, restore
the real Keychain, uninstall the real application, or qualify a signed release.
The complete App suite remains a separate local verification option; CI executes
the selected firmware/backend suites, not every native test.

VIA online importer runtime identity and the definition actually loaded in that
runtime remain unknown. This increment automates existing engineering evidence;
it cannot establish those sources or populate the empty support directory.
