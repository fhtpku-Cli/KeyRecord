import Foundation

public enum PhysicalSourceReadError: Error { case unavailable, malformed }

public struct PhysicalUsageMapping: Equatable, Sendable {
    public let source: UInt64
    public let destination: UInt64
    public init(source: UInt64, destination: UInt64) { self.source = source; self.destination = destination }
}

public struct PhysicalKeyboardService: Equatable, Sendable {
    public let registryID: UInt64
    public let mappings: [PhysicalUsageMapping]?
    public let identity: PhysicalKeyboardIdentity
    public init(registryID: UInt64, mappings: [PhysicalUsageMapping]?, identity: PhysicalKeyboardIdentity = .init()) {
        self.registryID = registryID; self.mappings = mappings; self.identity = identity
    }
}

public struct PhysicalSystemSnapshot: Equatable, Sendable {
    public let services: [PhysicalKeyboardService]
    public init(services: [PhysicalKeyboardService]) throws {
        guard services.count <= 256, Set(services.map(\.registryID)).count == services.count else {
            throw PhysicalSourceReadError.malformed
        }
        self.services = services.sorted { $0.registryID < $1.registryID }
    }
}

public protocol PhysicalSystemReading {
    func keyboardServiceIDs() throws -> [UInt64]
    func userKeyMapping(for registryID: UInt64) throws -> Any?
    func keyboardProperties(for registryID: UInt64) throws -> [String: Any]
}

public extension PhysicalSystemReading {
    func keyboardProperties(for registryID: UInt64) throws -> [String: Any] { [:] }
}

public enum PhysicalSystemSource {
    public static func mappings(_ property: Any?) throws -> [PhysicalUsageMapping]? {
        guard let property else { return nil }
        guard let entries = property as? [[String: Any]], entries.count <= 4096 else { throw PhysicalSourceReadError.malformed }
        func number(_ value: Any?) throws -> UInt64 {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  let result = UInt64(value.stringValue) else { throw PhysicalSourceReadError.malformed }
            return result
        }
        return try entries.map {
            guard Set($0.keys) == ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"] else {
                throw PhysicalSourceReadError.malformed
            }
            return try .init(source: number($0["HIDKeyboardModifierMappingSrc"]), destination: number($0["HIDKeyboardModifierMappingDst"]))
        }
    }

    public static func read(from port: any PhysicalSystemReading) throws -> PhysicalSystemSnapshot {
        let ids = try port.keyboardServiceIDs().sorted()
        guard ids.count <= 256, Set(ids).count == ids.count else { throw PhysicalSourceReadError.malformed }
        let result = try ids.map { id in
            let identity = try PhysicalKeyboardIdentity.parse(port.keyboardProperties(for: id))
            return try PhysicalKeyboardService(registryID: id, mappings: mappings(port.userKeyMapping(for: id)), identity: identity)
        }
        for service in result {
            guard try PhysicalKeyboardIdentity.parse(port.keyboardProperties(for: service.registryID)) == service.identity,
                  try mappings(port.userKeyMapping(for: service.registryID)) == service.mappings else {
                throw PhysicalSourceReadError.unavailable
            }
        }
        guard try port.keyboardServiceIDs().sorted() == ids else { throw PhysicalSourceReadError.unavailable }
        return try PhysicalSystemSnapshot(services: result)
    }
}

public struct PhysicalFirmwareReference: Equatable, Sendable {
    public let id: UUID
    public let device: String
    public let mapping: CanonicalTransform
    public let observedAt: Date
    public let layout: PhysicalLayoutReference?
    public init(device: String, mapping: CanonicalTransform, observedAt: Date, layout: PhysicalLayoutReference? = nil) {
        id = UUID()
        self.device = device; self.mapping = mapping; self.observedAt = observedAt
        self.layout = layout
    }
}

public enum PhysicalActiveSoftwareSource {
    public static func parse(_ data: Data, version: String?) throws -> PhysicalSoftwareReference {
        let parsed = try KarabinerReferenceParser.parse(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]] else { throw PhysicalSourceReadError.malformed }
        let selected = profiles.filter {
            guard let value = $0["selected"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return value.boolValue
        }
        guard selected.count == 1, let name = selected[0]["name"] as? String,
              parsed.profiles.filter({ $0.identityName == name }).count == 1 else { throw PhysicalSourceReadError.malformed }
        return .init(bytes: data, profile: name, version: version)
    }
}
