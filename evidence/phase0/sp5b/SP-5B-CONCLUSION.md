# SP-5B conclusion

Verdict: **BLOCKED**

Pinned source and the exact deterministic synthetic recorded-response fixture prove only whitelist-constrained non-changing queries and replay reconstruction of protocol version, UID, firmware-embedded definition pages, and keymap. The fixture sends FE/00 twice only to exercise the conceptual protocolVersion and uid public cases; the canonical source workflow reads both values from one FE/00 response. Outbound HID reports are not literally read-only, and synthetic replay does not prove device-side behavior or device compatibility.

The closed public report API has only protocolVersion, uid, definition, and keymapRead cases with no raw-byte initializer. Deny-all source and fake-transport tests make unknown operations and unlock, reset, bootloader, EEPROM, macro, encoder, settings, dynamic-entry, and keymap writes unrepresentable; rejected attempts made zero transport calls.

Live HID capture remains **BLOCKED** because the exact environment inventory has no approved Vial device and Vial is absent. No IOHID API was called, no device was enumerated or opened, no GUI was launched, and no report was sent to a real device.
