import Foundation

public struct PhysicalLayoutReference: Equatable, Sendable {
    public let name: String
    public let vendorProductID: UInt32
    public let geometry: CanonicalGeometry?
    public init(name: String, vendorProductID: UInt32, geometry: CanonicalGeometry?) {
        self.name = name; self.vendorProductID = vendorProductID; self.geometry = geometry
    }
}

public struct PhysicalKeyboardIdentity: Equatable, Sendable {
    public let vendorID: UInt32?
    public let productID: UInt32?
    public let transport: String?
    public let vendorIDSource: UInt32?

    public init(vendorID: UInt32? = nil, productID: UInt32? = nil, transport: String? = nil, vendorIDSource: UInt32? = nil) {
        self.vendorID = vendorID; self.productID = productID; self.transport = transport
        self.vendorIDSource = vendorIDSource
    }

    public static func parse(_ properties: [String: Any]) throws -> Self {
        func number(_ key: String) throws -> UInt32? {
            guard let raw = properties[key] else { return nil }
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  let number = UInt32(value.stringValue) else { throw PhysicalSourceReadError.malformed }
            return number
        }
        let transport: String?
        if let raw = properties["Transport"] {
            guard let text = raw as? String, !text.isEmpty, text.utf8.count <= 256 else { throw PhysicalSourceReadError.malformed }
            transport = text
        } else { transport = nil }
        return try .init(vendorID: number("VendorID"), productID: number("ProductID"), transport: transport,
                         vendorIDSource: number("VendorIDSource"))
    }
}

public struct PhysicalDeviceLayoutMatch: Equatable, Sendable {
    public let registryID: UInt64
    public let vendorProductID: UInt32
    public let layoutName: String
    public let geometry: CanonicalGeometry
}

public struct PhysicalDeviceLayoutResolution: Equatable, Sendable {
    public enum Status: String, Sendable {
        case matchedReference, missingLayout, missingGeometry, missingDevice, incompleteIdentity
        case unsupportedConnection, modelMismatch, ambiguous
    }
    public let status: Status
    public let match: PhysicalDeviceLayoutMatch?

    public static func resolve(input: PhysicalSourceInput, system: PhysicalSystemSnapshot?) -> Self {
        func unavailable(_ status: Status) -> Self { .init(status: status, match: nil) }
        guard let layout = input.layoutReference else { return unavailable(.missingLayout) }
        guard let geometry = layout.geometry, !geometry.positions.isEmpty else { return unavailable(.missingGeometry) }
        guard let system, !system.services.isEmpty else { return unavailable(.missingDevice) }
        guard system.services.allSatisfy({ $0.registryID != 0 && $0.identity.vendorID != nil &&
            $0.identity.productID != nil && $0.identity.transport != nil }) else { return unavailable(.incompleteIdentity) }
        let vendor = layout.vendorProductID >> 16, product = layout.vendorProductID & 0xffff
        guard vendor != 0 else { return unavailable(.incompleteIdentity) }
        let candidates = system.services.filter { $0.identity.vendorID == vendor && $0.identity.productID == product }
        guard !candidates.isEmpty else { return unavailable(.modelMismatch) }
        guard candidates.count == 1, let service = candidates.first else { return unavailable(.ambiguous) }
        // Bluetooth PnP source 2 names the USB-IF namespace; source 1 uses Bluetooth SIG IDs.
        // USB services can omit the source or report zero; their transport defines the namespace.
        let identity = service.identity
        switch identity.transport {
        case "USB":
            guard identity.vendorIDSource == nil || identity.vendorIDSource == 0 || identity.vendorIDSource == 2 else {
                return unavailable(.unsupportedConnection)
            }
        case "Bluetooth", "BluetoothLowEnergy":
            guard identity.vendorIDSource == 2 else { return unavailable(.unsupportedConnection) }
        default: return unavailable(.unsupportedConnection)
        }
        return .init(status: .matchedReference, match: .init(registryID: service.registryID,
            vendorProductID: layout.vendorProductID, layoutName: layout.name, geometry: geometry))
    }
}
