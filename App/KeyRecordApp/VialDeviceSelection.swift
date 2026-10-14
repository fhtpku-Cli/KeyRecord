import AppKit
import KeyRecordStore
import KeyRecordMappings
import KeyRecordDeviceRead

@MainActor
struct VialDeviceSelection {
    var devices: () throws -> [VialHIDDevice] = { try IOKitVialHIDEndpoint.availableDevices() }
    var choose: ([VialHIDDevice], NativeText) -> VialHIDDevice? = { devices, text in
        guard !devices.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = text("phase4.selectDevice")
        alert.informativeText = text("phase4.selectDeviceDetail")
        alert.addButton(withTitle: text("phase4.readSelectedDevice"))
        alert.addButton(withTitle: text("action.cancel"))
        alert.buttons[0].setAccessibilityIdentifier("vial.select.confirm")
        alert.buttons[1].setAccessibilityIdentifier("vial.select.cancel")
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        for (index, device) in devices.enumerated() {
            choices.addItem(withTitle: "\(index + 1). \(device.name) (\(String(format: "%04X:%04X", device.vendorID, device.productID)))")
        }
        alert.accessoryView = choices
        guard alert.runModal() == .alertFirstButtonReturn,
              devices.indices.contains(choices.indexOfSelectedItem) else { return nil }
        return devices[choices.indexOfSelectedItem]
    }
    var open: (VialHIDDevice) throws -> any VialHIDEndpoint = { device in
        try IOKitVialHIDEndpoint.open(registryEntryID: device.registryEntryID,
                                     vendorID: device.vendorID, productID: device.productID)
    }

    func connect(record: FirmwareBatchRecord, support: FirmwareSupportDirectory,
                 text: NativeText, authorize: () throws -> Void) throws -> VialDeviceReadConnection {
        try authorize()
        guard record.backend == .vial,
              support.supports(backend: record.backend, device: record.device, axes: record.axes)
        else { throw FirmwareError.unknownCompatibility }
        let candidates = try devices()
        try authorize()
        guard !candidates.isEmpty else { throw VialHIDError.disconnected }
        guard let selected = choose(candidates, text), candidates.contains(selected) else {
            throw CancellationError()
        }
        // A modal picker runs the event loop: lock or permission revocation can
        // happen while it is open. Recheck before the first device-side effect.
        try authorize()
        let endpoint = try open(selected)
        do { try authorize() } catch { endpoint.close(); throw error }
        return VialDeviceReadConnection(endpoint: endpoint, vendorID: selected.vendorID,
                                        productID: selected.productID)
    }
}
