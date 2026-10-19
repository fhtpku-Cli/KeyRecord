import Foundation
import KeyRecordMappings
import KeyRecordConfigurationRead
import KeyRecordLimitedXZ

public enum VialDefinitionError: Error, Equatable, Sendable {
    case invalidSize, invalidCompression, invalidDefinition, unsupportedLayout, changedDevice, busy
}
public struct VialDeviceDefinition: Sendable {
    public let uid: UInt64
    public let vendorID: UInt16
    public let productID: UInt16
    public let rows: Int
    public let columns: Int
    public let positions: Set<FirmwareSlot>
    public let encoderPositions: Set<FirmwareEncoderSlot>
    public let bytes: Data
    public let hasLayoutOptions: Bool
    public static let schema = "vial-embedded-json"
    public init(bytes: Data, uid: UInt64) throws {
        let root = try JSONDocumentRanges(bytes).root
        if let labels = root.members["layouts"]?.members["labels"] {
            guard let entries = labels.elements else { throw VialDefinitionError.invalidDefinition }
            hasLayoutOptions = !entries.isEmpty
        } else { hasLayoutOptions = false }
        func text(_ node: JSONDocumentRanges.Node?) throws -> String {
            guard let node else { throw VialDefinitionError.invalidDefinition }
            return try JSONDecoder().decode(String.self, from: Data(bytes[node.range]))
        }
        func dimension(_ field: String) throws -> Int {
            guard let node = root.members["matrix"]?.members[field],
                  let number = Int(String(decoding: bytes[node.range], as: UTF8.self)), (1...255).contains(number) else {
                throw VialDefinitionError.invalidDefinition
            }
            return number
        }
        let vid = try text(root.members["vendorId"]), pid = try text(root.members["productId"])
        guard vid.hasPrefix("0x"), pid.hasPrefix("0x"), let vendorID = UInt16(vid.dropFirst(2), radix: 16),
              let productID = UInt16(pid.dropFirst(2), radix: 16),
              let keymap = root.members["layouts"]?.members["keymap"]?.elements, !keymap.isEmpty else {
            throw VialDefinitionError.invalidDefinition
        }
        let rows = try dimension("rows"), columns = try dimension("cols")
        var positions: Set<FirmwareSlot> = []
        var encoderPositions: Set<FirmwareEncoderSlot> = []
        var alignment = 4
        var decal = false
        for (index, row) in keymap.enumerated() {
            if index == 0, bytes[row.range.lowerBound] == 123 { continue }
            guard let keys = row.elements else { throw VialDefinitionError.invalidDefinition }
            for key in keys {
                if bytes[key.range.lowerBound] == 123 {
                    if let a = key.members["a"] {
                        guard let value = Int(String(decoding: bytes[a.range], as: UTF8.self)), (0...7).contains(value) else {
                            throw VialDefinitionError.unsupportedLayout
                        }
                        alignment = value
                    }
                    if let d = key.members["d"] {
                        switch String(decoding: bytes[d.range], as: UTF8.self) {
                        case "true": decal = true
                        case "false": decal = false
                        default: throw VialDefinitionError.unsupportedLayout
                        }
                    }
                    continue
                }
                let label = try text(key)
                let fields = label.components(separatedBy: "\n")
                guard fields.count <= 12 else { throw VialDefinitionError.unsupportedLayout }
                // Alignment persists across rows; decal applies to only one key.
                // Only alignments 0/4 expose label 0; the center label carries "e".
                defer { decal = false }
                let coordinateText = alignment == 0 || alignment == 4 ? fields[0] : ""
                let center = [9, 6, 8, 0, 9, 6, 8, 0][alignment]
                let encoder = fields.indices.contains(center) && fields[center] == "e"
                if !encoder, !coordinateText.contains(",") {
                    if decal {
                        // Upstream includes an unpositioned decal at matrix (0,0)
                        // in rowcol and save_layout, so readback must compare it.
                        positions.insert(.init(layer: 0, row: 0, column: 0))
                    } else if !coordinateText.isEmpty {
                        throw VialDefinitionError.invalidDefinition
                    }
                    continue
                }
                let coordinate = coordinateText.split(separator: ",", omittingEmptySubsequences: false)
                guard coordinate.count == 2, let r = Int(coordinate[0]), let c = Int(coordinate[1]) else {
                    throw VialDefinitionError.invalidDefinition
                }
                if encoder {
                    guard (0...255).contains(r), let direction = FirmwareEncoderDirection(rawValue: c) else {
                        throw VialDefinitionError.invalidDefinition
                    }
                    encoderPositions.insert(.init(layer: 0, index: r, direction: direction))
                } else {
                    guard r >= 0, r < rows, c >= 0, c < columns else { throw VialDefinitionError.invalidDefinition }
                    positions.insert(.init(layer: 0, row: r, column: c))
                }
            }
        }
        guard !positions.isEmpty else { throw VialDefinitionError.invalidDefinition }
        self.uid = uid; self.vendorID = vendorID; self.productID = productID
        self.rows = rows; self.columns = columns; self.positions = positions; self.bytes = bytes
        self.encoderPositions = encoderPositions
    }
}
public enum VialXZDecoder {
    public static let maximumCompressedBytes = 131_072
    public static let maximumDecodedBytes = 1_048_576
    public static func decode(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count <= maximumCompressedBytes else { throw VialDefinitionError.invalidSize }
        var output = [UInt8](repeating: 0, count: maximumDecodedBytes), written = 0
        let status = try bytes.withUnsafeBytes { input in
            try output.withUnsafeMutableBufferPointer { output in
                guard let source = input.bindMemory(to: UInt8.self).baseAddress, let destination = output.baseAddress else {
                    throw VialDefinitionError.invalidCompression
                }
                return keyrecord_decode_xz(source, bytes.count, destination, output.count, &written)
            }
        }
        guard status == 0, written > 0 else { throw VialDefinitionError.invalidCompression }
        return Data(output.prefix(written))
    }
}
public actor VialDefinitionReader {
    private let transport: any VialReadTransport
    private var busy = false
    public init(transport: any VialReadTransport) { self.transport = transport }
    public func read(expectedUID: UInt64, authorize: @Sendable () throws -> Void = {}) async throws -> VialDeviceDefinition {
        guard !busy else { throw VialDefinitionError.busy }; busy = true; defer { busy = false }
        func response(_ request: VialReadRequest) async throws -> [UInt8] {
            try Task.checkCancellation(); try authorize()
            let result = try await transport.exchange(request, timeoutMilliseconds: 1000)
            try Task.checkCancellation(); try authorize()
            guard result.count == 32 else { throw VialHIDError.invalidReport }
            return result
        }
        let via = try await response(.viaProtocol)
        guard via.prefix(3).elementsEqual([1, 0, 9]) else { throw VialReadbackError.unsupportedProtocol }
        let identity = try await response(.identity)
        guard identity.prefix(4).elementsEqual([6, 0, 0, 0]) else { throw VialReadbackError.unsupportedProtocol }
        let uid = identity[4..<12].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        guard uid == expectedUID else { throw VialReadbackError.wrongDevice }
        let sizeBytes = try await response(.definitionSize)
        let size = sizeBytes.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard size > 0, size <= VialXZDecoder.maximumCompressedBytes else { throw VialDefinitionError.invalidSize }
        var compressed: [UInt8] = []
        for page in 0..<((size + 31) / 32) {
            let data = try await response(.definitionPage(UInt16(page)))
            compressed.append(contentsOf: data.prefix(min(32, size - compressed.count)))
        }
        let finalIdentity = try await response(.identity)
        guard finalIdentity.prefix(12).elementsEqual(identity.prefix(12)) else { throw VialDefinitionError.changedDevice }
        let decoded = try VialXZDecoder.decode(Data(compressed))
        try Task.checkCancellation(); try authorize()
        return try VialDeviceDefinition(bytes: decoded, uid: uid)
    }
}
// One selected connection belongs to one readback operation. Closing is
// synchronous so a UI selection/privacy change can stop pending I/O immediately.
public final class VialDeviceReadConnection: Sendable {
    private let transport: VialHIDTransport
    private let session: VialDeviceReadSession
    public init(endpoint: any VialHIDEndpoint, vendorID: UInt16, productID: UInt16,
                deadline: any VialHIDDeadline = DispatchVialHIDDeadline()) {
        let transport = VialHIDTransport(endpoint: endpoint, deadline: deadline)
        self.transport = transport
        session = VialDeviceReadSession(transport: transport, vendorID: vendorID, productID: productID)
    }
    deinit { transport.close() }
    public func close() { transport.close() }
    public func observe(record: FirmwareBatchRecord, original: Data,
                        authorize: @escaping @Sendable () throws -> Void) async throws -> VialKeymapObservation {
        defer { close() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await session.observe(record: record, original: original, authorize: authorize)
        } onCancel: { self.close() }
    }
}

public actor VialDeviceReadSession {
    private let transport: any VialReadTransport
    private let vendorID: UInt16
    private let productID: UInt16
    private var busy = false
    public init(transport: any VialReadTransport, vendorID: UInt16, productID: UInt16) {
        self.transport = transport; self.vendorID = vendorID; self.productID = productID
    }
    public func observe(record: FirmwareBatchRecord, original: Data,
                        authorize: @escaping @Sendable () throws -> Void = {},
                        at date: @Sendable () -> Date = { Date() }) async throws -> VialKeymapObservation {
        guard !busy else { throw VialDefinitionError.busy }; busy = true; defer { busy = false }
        guard record.backend == .vial, let uid = UInt64(record.device), record.axes.definitionSchema == VialDeviceDefinition.schema,
              record.axes.deviceProtocol == "via-9/vial-6", record.axes.layoutFormat == "vial-save-1",
              record.axes.keycodeDialect == VialKeycodeDialect.name else {
            throw FirmwareError.unknownCompatibility
        }
        let definition = try await VialDefinitionReader(transport: transport).read(expectedUID: uid, authorize: authorize)
        guard definition.vendorID == vendorID, definition.productID == productID else { throw VialHIDError.wrongInterface }
        let document = try FirmwareDocument(bytes: original, backend: .vial)
        guard document.device == record.device, let dimensions = document.matrixDimensions,
              dimensions.rows == definition.rows, dimensions.columns == definition.columns else { throw VialReadbackError.invalidMatrix }
        // Check every layer's occupied positions, not just the flattened byte count.
        let values = try document.slotValues()
        for layer in 0..<dimensions.layers {
            let positions = Set(values.keys.filter { $0.layer == layer }.map { FirmwareSlot(layer: 0, row: $0.row, column: $0.column) })
            guard positions == definition.positions else { throw VialReadbackError.invalidMatrix }
        }
        // Upstream reads both directions for every declared index, even when KLE
        // shows only one direction. These are not matrix positions.
        let adapter = try VialReadbackAdapter(transport: transport, matrixRows: definition.rows, matrixColumns: definition.columns,
            encoderIndices: Set(definition.encoderPositions.map(\.index)), hasLayoutOptions: definition.hasLayoutOptions)
        let observation = try await adapter.observe(record: record, original: original, authorize: authorize, at: date)
        let finalDefinition = try await VialDefinitionReader(transport: transport).read(expectedUID: uid, authorize: authorize)
        guard finalDefinition.bytes == definition.bytes else { throw VialDefinitionError.changedDevice }
        try Task.checkCancellation(); try authorize()
        return VialKeymapObservation(device: observation.device, axes: observation.axes, values: observation.values,
            encoderValues: observation.encoderValues, dynamicEntries: observation.dynamicEntries,
            configurationValues: observation.configurationValues, observedAt: date(),
            definition: .init(device: String(definition.uid), bytes: definition.bytes))
    }
}
