import Foundation

struct VialConfigurationReader {
    let response: @Sendable (VialReadRequest) async throws -> [UInt8]
    let hasLayoutOptions: Bool?

    func read(_ document: FirmwareDocument) async throws -> [VialConfigurationSection: Data] {
        var values: [VialConfigurationSection: Data] = [:]
        for section in VialConfigurationSection.allCases {
            guard let expected = try document.configurationValue(section) else { continue }
            switch section {
            case .macro: values[section] = try await macros()
            case .layoutOptions:
                if hasLayoutOptions == false { values[section] = Data([0]) }
                else if expected.first == 1 {
                    let reply = try await response(.layoutOptions)
                    guard reply.prefix(2) == [2, 2] else { throw VialReadbackError.malformedResponse }
                    values[section] = Data([1] + reply[2..<6])
                }
            case .settings: values[section] = try await settings()
            }
        }
        return values
    }
    private func macroInfo() async throws -> (count: Int, size: Int) {
        let count = try await response(.macroCount), size = try await response(.macroSize)
        guard count[0] == 0x0c, size[0] == 0x0d else { throw VialReadbackError.malformedResponse }
        return (Int(count[1]), Int(size[1]) << 8 | Int(size[2]))
    }
    private func macros() async throws -> Data {
        let info = try await macroInfo()
        var buffer: [UInt8] = [], strings: [[UInt8]] = [], current: [UInt8] = []
        while buffer.count < info.size && strings.count < info.count {
            let length = min(28, info.size - buffer.count)
            let request = try VialReadRequest.macroBuffer(offset: UInt16(buffer.count), length: UInt8(length))
            let reply = try await response(request)
            guard reply.prefix(4) == request.bytes.prefix(4) else { throw VialReadbackError.malformedResponse }
            buffer += reply[4..<(4 + length)]
            for byte in reply[4..<(4 + length)] where strings.count < info.count {
                if byte == 0 { try validateMacro(current); strings.append(current); current = [] }
                else { current.append(byte) }
            }
        }
        guard strings.count == info.count else { throw VialReadbackError.malformedResponse }
        let final = try await macroInfo()
        guard info == final else { throw VialReadbackError.changedDevice }
        return Data([UInt8(info.count)] + strings.flatMap { $0 + [0] })
    }
    private func validateMacro(_ bytes: [UInt8]) throws {
        var index = 0
        while index < bytes.count {
            if bytes[index] != 1 { index += 1; continue }
            guard index + 1 < bytes.count, (1...7).contains(bytes[index + 1]) else { throw VialReadbackError.malformedResponse }
            let length = bytes[index + 1] <= 3 ? 3 : 4
            guard index + length <= bytes.count else { throw VialReadbackError.malformedResponse }
            index += length
        }
    }
    private func settingIDs() async throws -> [UInt16] {
        var ids: [UInt16] = [], cursor: UInt16 = 0
        while true {
            let bytes = try await response(.settingsQuery(after: cursor))
            var ended = false
            for offset in stride(from: 0, to: 32, by: 2) {
                let id = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                if id == .max { ended = true; continue }
                guard !ended, id > cursor else { throw VialReadbackError.malformedResponse }
                ids.append(id); cursor = id
            }
            if ended { return ids }
        }
    }
    private func settings() async throws -> Data? {
        let ids = try await settingIDs()
        guard ids.allSatisfy({ VialSettingsSchema.width($0) != nil }) else { return nil }
        var values: [UInt16: [UInt8]] = [:]
        for id in ids {
            let bytes = try await response(.setting(id))
            guard bytes[0] == 0, let width = VialSettingsSchema.width(id) else { throw VialReadbackError.malformedResponse }
            values[id] = Array(bytes[1..<(1 + width)])
        }
        guard try await settingIDs() == ids else { throw VialReadbackError.changedDevice }
        return VialSettingsSchema.encode(values)
    }
}
