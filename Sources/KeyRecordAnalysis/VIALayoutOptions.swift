import Foundation

public struct VIALayoutOption: Equatable, Sendable {
    public let title: String
    public let choices: [String]
    public let isToggle: Bool

    var bitWidth: Int { Int.bitWidth - (choices.count - 1).leadingZeroBitCount }

    static func parse(_ value: VIAJSONValue?) throws -> [Self] {
        guard let value else { return [] }
        guard let labels = value.array else { throw VIAImportError.invalidGeometry }
        let options = try labels.map { label -> Self in
            if let title = label.string, !title.isEmpty {
                return .init(title: String(title.prefix(256)), choices: ["0", "1"], isToggle: true)
            }
            guard let fields = label.array, fields.count >= 3,
                  fields.allSatisfy({ $0.string?.isEmpty == false }) else { throw VIAImportError.invalidGeometry }
            return .init(title: String(fields[0].string!.prefix(256)),
                         choices: fields.dropFirst().map { String($0.string!.prefix(256)) }, isToggle: false)
        }
        guard options.reduce(0, { $0 + $1.bitWidth }) <= 32 else { throw VIAImportError.invalidGeometry }
        return options
    }

    static func selection(_ explicit: [Int]?, packed: UInt32?, options: [Self]) throws -> [Int]? {
        guard explicit == nil || packed == nil else { throw VIAImportError.invalidGeometry }
        var result = explicit
        if let packed {
            var remaining = UInt64(packed)
            var reversed: [Int] = []
            for option in options.reversed() {
                reversed.append(Int(remaining & ((1 << option.bitWidth) - 1)))
                remaining >>= option.bitWidth
            }
            guard remaining == 0 else { throw VIAImportError.invalidGeometry }
            result = reversed.reversed()
        }
        if let result {
            guard result.count == options.count,
                  zip(result, options).allSatisfy({ $1.choices.indices.contains($0) }) else {
                throw VIAImportError.invalidGeometry
            }
        }
        return result ?? (options.isEmpty ? [] : nil)
    }
}
