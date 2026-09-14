import Foundation

extension ChordBucket {
    static func ordered(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.chord.keyCode != rhs.chord.keyCode { return lhs.chord.keyCode.value < rhs.chord.keyCode.value }
        return lhs.orderingComponents.lexicographicallyPrecedes(rhs.orderingComponents)
    }

    private var orderingComponents: [String] {
        let modifiers = chord.modifiers
        let bucket: [String]
        switch appBucket {
        case .unknown: bucket = ["0", ""]
        case .bundleID(let identifier): bucket = ["1", identifier]
        }
        return [modifiers.command.rawValue, modifiers.option.rawValue, modifiers.control.rawValue,
            modifiers.shift.rawValue, modifiers.fn.rawValue] + bucket
    }
}
