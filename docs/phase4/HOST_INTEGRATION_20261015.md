# Production composition and explicit Vial device selection

The production composition now passes host-provided Karabiner version/authority,
firmware support and independent version axes to the existing deployment coordinators.
The application no longer needs a fixture to reconfigure individual models after boot.
Defaults retain the empty qualified support directory and unknown independent axes;
neither a file's claimed version nor a local device's presence grants compatibility.

For a qualified Vial readback request, the native selector lists only the raw-HID
interface (usage page 0xff60, usage 0x61, 32-byte reports). Listing reads IORegistry
properties without opening devices. The user selects one registry entry; the existing
endpoint rechecks vendor/product/interface before opening it. Independent Vial UID,
definition, topology, protocol, complete keymap and encoder checks remain in the existing
readback session. No firmware write/import command is added.

The current privacy generation and readback request are checked before discovery,
after discovery, after the modal picker, and after opening. Cancelling readback while
the picker is open prevents opening the device; revocation during open closes the
returned endpoint. Existing in-flight cancellation still closes the active connection.

## Offline evidence and remaining work

- Production composition tested with injected temporary Karabiner configuration and
  firmware version/support facts; firmware export/import claim reaches device discovery.
  No device selection leaves import merely claimed, never verified.
- Unknown support is rejected before discovery; cancelled, unlisted and locked choices
  never open an endpoint; lock during open closes it. Cancellation of the originating
  readback inside the picker also prevents open.
- Native English and Chinese NSAlert controls execute with injected synthetic device
  lists and endpoint factories. Existing packet/definition/matrix/encoder tests remain.
- The production defaults still cannot authorize a Karabiner write or a firmware patch
  for an unqualified device. Production support entries, real version axes, Karabiner
  reload/effect/disable timing, actual HID enumeration/readback, official importer and
  real keyboard verification remain deferred. This is source integration, not G3/G4 or
  release qualification. The registry discovery function was compiled, not run on the
  user's real devices.
- No real uninstall or data deletion was performed. Recovery copy verification before
  deleting local data is unchanged. No new hash, frozen contract, baseline or gate.
