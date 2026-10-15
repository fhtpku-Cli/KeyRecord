import AppKit
import Darwin
import KeyRecordStore
import KeyRecordMappings
import KeyRecordDeviceRead

@MainActor
struct FirmwareImporterVersionSource {
    var locate: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    func version(for backend: FirmwareBackend) -> String? {
        guard backend == .vial, let bundle = locate("today.vial") else { return nil }
        let file = bundle.appendingPathComponent("Contents/Info.plist")
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size > 0, status.st_size <= 65_536 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 65_537), count = 0
        while count < bytes.count {
            let readCount = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress!.advanced(by: count), $0.count - count) }
            if readCount < 0 { if errno == EINTR { continue }; return nil }
            if readCount == 0 { break }
            count += readCount
        }
        guard count <= 65_536,
              let info = try? PropertyListSerialization.propertyList(from: Data(bytes.prefix(count)), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "today.vial",
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        guard [version, build].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return "today.vial/\(version)/\(build)"
    }
}

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

    func openVIAVersionSource(device: String, text: NativeText, authorize: () throws -> Void) throws -> VIAVersionReadConnection {
        try authorize()
        let candidates = try devices().filter { String(UInt32($0.vendorID) << 16 | UInt32($0.productID)) == device }
        try authorize()
        guard !candidates.isEmpty else { throw VialHIDError.disconnected }
        guard let selected = choose(candidates, text), candidates.contains(selected) else { throw CancellationError() }
        try authorize()
        let endpoint = try open(selected)
        do { try authorize() } catch { endpoint.close(); throw error }
        return VIAVersionReadConnection(endpoint: endpoint, vendorID: selected.vendorID, productID: selected.productID)
    }

    func openSelectedDevice(record: FirmwareBatchRecord, support: FirmwareSupportDirectory,
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
