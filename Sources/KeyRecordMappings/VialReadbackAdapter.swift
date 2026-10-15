import Foundation

public enum VialReadbackError: Error, Equatable, Sendable {
    case invalidRequest, malformedResponse, unsupportedProtocol, wrongDevice, changedDevice, invalidMatrix, invalidEncoders, busy
}
public struct VialReadRequest: Equatable, Sendable {
    public let bytes: [UInt8]
    private init(_ prefix: [UInt8]) { bytes = prefix + Array(repeating: 0, count: 32 - prefix.count) }
    public static let viaProtocol = VialReadRequest([0x01])
    public static let viaKeycodesVersion = VialReadRequest([0x02, 0x06])
    public static let identity = VialReadRequest([0xfe, 0x00])
    public static let layerCount = VialReadRequest([0x11])
    public static let definitionSize = VialReadRequest([0xfe, 0x01])
    public static let dynamicCounts = VialReadRequest([0xfe, 0x0d, 0])
    public static func dynamicEntry(_ section: VialDynamicSection, index: UInt8) -> VialReadRequest {
        VialReadRequest([0xfe, 0x0d, section.command, index])
    }
    public static func encoder(layer: UInt8, index: UInt8) -> VialReadRequest {
        VialReadRequest([0xfe, 0x03, layer, index])
    }
    public static func definitionPage(_ page: UInt16) throws -> VialReadRequest {
        guard page < 4096 else { throw VialReadbackError.invalidRequest }
        return VialReadRequest([0xfe, 0x02, UInt8(page & 255), UInt8(page >> 8)])
    }
    public static func keymap(offset: UInt16, length: UInt8) throws -> VialReadRequest {
        guard length > 0, length <= 28, Int(offset) + Int(length) <= 65_536 else { throw VialReadbackError.invalidRequest }
        return VialReadRequest([0x12, UInt8(offset >> 8), UInt8(offset & 255), length])
    }
}
public protocol VialReadTransport: Sendable {
    // A future HID port owns report-ID framing, device binding and bounded I/O.
    // This interface carries only typed, 32-byte read requests; errors propagate.
    func exchange(_ request: VialReadRequest, timeoutMilliseconds: Int) async throws -> [UInt8]
}
public actor VialReadbackAdapter {
    private let transport: any VialReadTransport
    private let timeoutMilliseconds: Int
    private let matrixRows: Int
    private let matrixColumns: Int
    private let encoderIndices: Set<Int>
    private var busy = false
    private var authorization: (@Sendable () throws -> Void)?
    public init(transport: any VialReadTransport, matrixRows: Int, matrixColumns: Int,
                encoderIndices: Set<Int> = [], timeoutMilliseconds: Int = 1000) throws {
        guard timeoutMilliseconds > 0 else { throw VialReadbackError.invalidRequest }
        guard (1...255).contains(matrixRows), (1...255).contains(matrixColumns) else { throw VialReadbackError.invalidMatrix }
        guard encoderIndices.allSatisfy({ (0...255).contains($0) }) else { throw VialReadbackError.invalidEncoders }
        self.transport = transport; self.timeoutMilliseconds = timeoutMilliseconds
        self.matrixRows = matrixRows; self.matrixColumns = matrixColumns
        self.encoderIndices = encoderIndices
    }
    public func observe(record: FirmwareBatchRecord, original: Data,
                        authorize: @escaping @Sendable () throws -> Void = {},
                        at date: @Sendable () -> Date = { Date() }) async throws -> VialKeymapObservation {
        guard !busy else { throw VialReadbackError.busy }
        busy = true; authorization = authorize
        defer { busy = false; authorization = nil }
        try authorize()
        guard record.backend == .vial, record.axes.deviceProtocol == "via-9/vial-6",
              record.axes.keycodeDialect == VialKeycodeDialect.name, record.axes.layoutFormat == "vial-save-1" else {
            throw VialReadbackError.unsupportedProtocol
        }
        let document = try FirmwareDocument(bytes: original, backend: .vial)
        let fileAxes = try FirmwareVersionProvider.axes(bytes: original, backend: .vial)
        guard fileAxes.deviceProtocol == record.axes.deviceProtocol, fileAxes.keycodeDialect == record.axes.keycodeDialect else {
            throw VialReadbackError.unsupportedProtocol
        }
        guard document.device == record.device, let expectedUID = UInt64(record.device) else { throw VialReadbackError.wrongDevice }
        // Matrix dimensions come from the caller's independently checked definition,
        // not a guess based on an export's flattened byte count.
        guard let shape = document.matrixDimensions, shape.layers <= 255,
              shape.rows == matrixRows, shape.columns == matrixColumns else {
            throw VialReadbackError.invalidMatrix
        }
        let size = shape.layers * shape.rows * shape.columns * 2
        guard size > 0, size <= 65_536 else { throw VialReadbackError.invalidMatrix }
        let fileEncoders = try document.encoderValues()
        let expectedEncoders = Set((0..<shape.layers).flatMap { layer in
            encoderIndices.flatMap { index in
                [FirmwareEncoderSlot(layer: layer, index: index, direction: .clockwise),
                 FirmwareEncoderSlot(layer: layer, index: index, direction: .counterclockwise)]
            }
        })
        guard document.encoderCount == (encoderIndices.max().map { $0 + 1 } ?? 0),
              Set(fileEncoders.keys) == expectedEncoders else { throw VialReadbackError.invalidEncoders }
        try Task.checkCancellation()
        let via = try await response(.viaProtocol)
        guard via[0] == 0x01, via[1] == 0, via[2] == 9 else { throw VialReadbackError.unsupportedProtocol }
        let identity = try await response(.identity)
        guard identity.prefix(4).elementsEqual([6, 0, 0, 0]) else { throw VialReadbackError.unsupportedProtocol }
        let uid = identity[4..<12].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        guard uid == expectedUID else { throw VialReadbackError.wrongDevice }
        let layers = try await response(.layerCount)
        guard layers[0] == 0x11, Int(layers[1]) == shape.layers else { throw VialReadbackError.invalidMatrix }
        var keymap: [UInt8] = []
        while keymap.count < size {
            let length = UInt8(min(28, size - keymap.count))
            let request = try VialReadRequest.keymap(offset: UInt16(keymap.count), length: length)
            let bytes = try await response(request)
            guard bytes.prefix(4).elementsEqual(request.bytes.prefix(4)) else { throw VialReadbackError.malformedResponse }
            keymap.append(contentsOf: bytes[4..<(4 + Int(length))])
        }
        var encoderValues: [FirmwareEncoderSlot: String] = [:]
        for layer in 0..<shape.layers {
            for index in encoderIndices.sorted() {
                let bytes = try await response(.encoder(layer: UInt8(layer), index: UInt8(index)))
                // GET_ENCODER has no echoed request header; both values are big-endian.
                encoderValues[.init(layer: layer, index: index, direction: .clockwise)] =
                    VialKeycodeDialect.token(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
                encoderValues[.init(layer: layer, index: index, direction: .counterclockwise)] =
                    VialKeycodeDialect.token(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
            }
        }
        var dynamic: [VialDynamicSection: [[UInt8]]] = [:]
        let sections = try Set(document.unverifiedVialSections())
        let requested = try VialDynamicSection.allCases.filter {
            guard sections.contains($0.rawValue) else { return false }
            return try document.dynamicEntries($0) != nil
        }
        if !requested.isEmpty {
            let counts = try await response(.dynamicCounts)
            for section in requested {
                var entries: [[UInt8]] = []
                for index in 0..<Int(counts[section.countIndex]) {
                    let entry = try await response(.dynamicEntry(section, index: UInt8(index)))
                    guard entry[0] == 0 else { throw VialReadbackError.malformedResponse }
                    entries.append(Array(entry[1..<(1 + section.byteCount)]))
                }
                dynamic[section] = entries
            }
            let finalCounts = try await response(.dynamicCounts)
            guard finalCounts == counts else { throw VialReadbackError.changedDevice }
        }
        // Reject a disconnect/rebind or layer-count change across the multi-report read.
        let finalIdentity = try await response(.identity), finalLayers = try await response(.layerCount)
        guard finalIdentity.prefix(12).elementsEqual(identity.prefix(12)), finalLayers.prefix(2).elementsEqual(layers.prefix(2)) else {
            throw VialReadbackError.changedDevice
        }
        var values: [FirmwareSlot: String] = [:]
        for slot in try document.slotValues().keys {
            let offset = ((slot.layer * shape.rows + slot.row) * shape.columns + slot.column) * 2
            values[slot] = VialKeycodeDialect.token(UInt16(keymap[offset]) << 8 | UInt16(keymap[offset + 1]))
        }
        try Task.checkCancellation()
        return VialKeymapObservation(device: String(uid), axes: record.axes, values: values, encoderValues: encoderValues,
                                    dynamicEntries: dynamic, observedAt: date())
    }
    private func response(_ request: VialReadRequest) async throws -> [UInt8] {
        try Task.checkCancellation()
        try authorization?()
        let bytes = try await transport.exchange(request, timeoutMilliseconds: timeoutMilliseconds)
        try Task.checkCancellation()
        try authorization?()
        guard bytes.count == 32 else { throw VialReadbackError.malformedResponse }
        return bytes
    }
}
