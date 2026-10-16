# VIA file layer-tap destination bounds

A malformed or hand-edited VIA file can contain `LT(16,KC_A)` through
`LT(31,KC_A)`. The official VIA converter masks the layer with `0xf`, so these
values address layers 0 through 15, not the layers written in the file.
KeyRecord's new file workflow accepted those spellings as evidence that layers
16 through 31 were reachable. It could preview and export changes on an
unreachable layer.

On main `f23a575`, a regression exercising all 32 layer numbers in manual and
automatic mode recorded 36 failed assertions. These included an actual
encrypted transaction that previewed the invalid destination, wrote the export
file, and entered `awaitingUserImport`.

The fix restricts `LT` reachability to canonical layer numbers 0 through 15.
The file itself remains retainable as a recovery original; its contents are
not normalized. Layer entry replacement stays protected. Other supported
layer actions retain their existing 0 through 31 range.

Validation covers valid and invalid `LT` destinations, both editing modes,
`MO(31)` as a valid upper-layer control, and rejection before external export.
The encrypted original remains byte-identical and the rejected operation stays
a draft without a pending transaction. The existing official VIA oracle also
executes the upstream converter and reverse converter for all 32 destinations
across nine dictionary variants, retaining the existing file import checks.
All 798 local package tests and the official VIA oracle passed after the fix.
Temporary reproduction and verification logs use `/private/tmp/keyrecord-via-lt-*`.

This is offline file-workflow evidence. Physical keyboard behavior, real VIA
import, Keychain recovery, uninstall and release validation remain deferred.
No new hash, frozen contract, baseline or gate is introduced.
