# VIA file editing with actual position and key choices

The previous production file editor accepted arbitrary 0–255 layer/position
numbers and a free-text keycode. Users had to infer the original key and could
only discover protected entries or invalid positions at preview time. Valid
file positions above 255 were also inaccessible from those controls.

The file editor now loads the latest retained original through the encrypted
coordinator, lists its actual layers and positions, displays the original key,
and offers the existing 90 basic output keys by readable names in both languages.
Users explicitly select a position and output before adding a change. The list
does not infer physical geometry; repeated or ambiguous keys require checking
the corresponding VIA configuration/definition. Output search filters the list,
not the compatibility policy. This does not add chord, macro, encoder or
application-specific editing.

The position catalog and final patch share the existing source-entry checks.
Layer entries, unknown actions and unreachable layers remain visible with a
reason but cannot be staged through the selector. Preview/export independently
revalidate the original and every change, even if a caller bypasses the UI.
Old records without explicit file compatibility do not gain this capability.
New originals invalidate old catalogs; privacy closing clears them. Reopening
uses the saved original, not whatever file is currently selected in the importer.
Catalogs are transient and add no persisted payload or telemetry.

Existing preview, separate export, import declaration, behavior confirmation,
original export and guided restoration remain available. After export, the UI
explains manual import into VIA for the same keyboard, actual key testing and
recovery. An export or import declaration does not become verified behavior.
Vial and legacy device-qualified editing keep their existing controls.

## Verification

Regression coverage compares each catalog restriction with actual patch behavior,
including protected/unknown actions and unreachable layers; checks valid positions
above 255; rejects old records and superseded originals; and checks encrypted
reopen and privacy withdrawal. Native tests select actual positions and outputs,
exercise protected/unknown explanations in English and Chinese, and complete
preview/export through the production file entry using a temporary encrypted
store. The existing official VIA importer oracle and firmware regression CI
remain required.

Local full package tests passed 801 cases. The firmware native suites passed
104 cases using temporary stores and synthetic endpoints; unsigned Debug
build-for-testing also passed. Native screenshots cover the editor at 640 px
in English and Chinese. Self-review caught missing explicit keyboard focus
and keyboard activation on the new choice buttons; explicit focus and Space/Return
handling fix them. The native test retains the focus assertion and actual Space
key down/up selection. These results do not establish real device qualification.

## Deferred scope

Real keyboard effects, official GUI import, HID, Keychain recovery, uninstall
and release qualification remain deferred. Device support defaults stay empty;
file choices do not grant device support. Recovery/deletion review and all
existing compatibility checks remain. No new hash, frozen contract, baseline
or gate was introduced. Recurring automation remains deleted; this batch ends
after review, PR CI, merge and main CI.
