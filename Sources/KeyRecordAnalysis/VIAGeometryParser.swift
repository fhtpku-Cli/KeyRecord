import Foundation

enum VIAGeometryParser {
    typealias Result = (geometry: CanonicalGeometry?, limitations: Set<VIAReferenceLimitation>)

    private struct Key {
        let row: Int, column: Int
        var x: Double, y: Double
        let width: Double, height: Double, rotation: Double, rx: Double, ry: Double
        var group: Int? = nil
        var choice: Int? = nil

        func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
            let radians = rotation.truncatingRemainder(dividingBy: 360) * .pi / 180
            return (rx + (x - rx) * cos(radians) - (y - ry) * sin(radians),
                    ry + (x - rx) * sin(radians) + (y - ry) * cos(radians))
        }
        var corners: [(Double, Double)] {
            [(x, y), (x + width, y), (x, y + height), (x + width, y + height)].map { rotate($0, $1) }
        }
        func position(origin: (Double, Double)) throws -> PhysicalPosition {
            let center = rotate(x + width / 2, y + height / 2)
            guard center.0.isFinite, center.1.isFinite else { throw VIAImportError.invalidGeometry }
            return try .init(id: "\(row),\(column)", centerX: center.0 - origin.0,
                             centerY: center.1 - origin.1, coordinateFrame: "via-definition-reference")
        }
    }

    private static func pair(_ text: String) throws -> (Int, Int) {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let first = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let second = Int(parts[1].trimmingCharacters(in: .whitespaces)), first >= 0, second >= 0 else {
            throw VIAImportError.invalidGeometry
        }
        return (first, second)
    }

    static func kle(_ keymap: [VIAJSONValue], rows: Int, cols: Int,
                    options: [VIALayoutOption], selection: [Int]?) throws -> Result {
        var y = 0.0, rotation = 0.0, rx = 0.0, ry = 0.0
        var keys: [Key] = []
        let decorative: Set<String> = ["c", "t", "a", "f", "f2", "fa", "p", "sm", "sb", "st", "n", "g"]
        for row in keymap {
            guard let items = row.array else { throw VIAImportError.invalidGeometry }
            var x = 0.0, width = 1.0, height = 1.0
            for (index, item) in items.enumerated() {
                if let properties = item.object {
                    guard Set(properties.keys).isSubset(of: decorative.union(["x", "y", "w", "h", "r", "rx", "ry"])) else {
                        return (nil, [.complexGeometry])
                    }
                    if let alignment = properties["a"] {
                        guard alignment.integer == 0 || alignment.integer == 4 else { return (nil, [.complexGeometry]) }
                    }
                    if properties["g"] == .bool(true) { return (nil, [.complexGeometry]) }
                    if !Set(properties.keys).isDisjoint(with: ["r", "rx", "ry"]), index != 0 {
                        return (nil, [.complexGeometry])
                    }
                    for field in ["r", "rx", "ry", "x", "y", "w", "h"] where properties[field] != nil {
                        guard let number = properties[field]?.number, number.isFinite else { throw VIAImportError.invalidGeometry }
                        switch field {
                        case "r": rotation = number
                        case "rx": rx = number; y = ry
                        case "ry": ry = number; y = ry
                        case "x": x += number
                        case "y": y += number
                        case "w": width = number
                        case "h": height = number
                        default: break
                        }
                    }
                } else if let label = item.string {
                    let labels = label.components(separatedBy: "\n")
                    guard labels.enumerated().allSatisfy({ $0.offset == 0 || $0.offset == 3 || $0.element.isEmpty }) else {
                        return (nil, [.complexGeometry])
                    }
                    let (r, c) = try pair(labels[0])
                    guard r < rows, c < cols, width > 0, height > 0,
                          [x + rx, y, width, height].allSatisfy(\.isFinite) else { throw VIAImportError.invalidGeometry }
                    var key = Key(row: r, column: c, x: x + rx, y: y, width: width, height: height,
                                  rotation: rotation, rx: rx, ry: ry)
                    if labels.count > 3, !labels[3].isEmpty {
                        let (group, choice) = try pair(labels[3])
                        guard options.indices.contains(group), options[group].choices.indices.contains(choice) else {
                            throw VIAImportError.invalidGeometry
                        }
                        key.group = group; key.choice = choice
                    }
                    keys.append(key)
                    x += width; width = 1; height = 1
                } else { throw VIAImportError.invalidGeometry }
            }
            y += 1
        }
        guard !keys.isEmpty else { throw VIAImportError.invalidGeometry }
        guard let selection else { return (nil, [.layoutOptions]) }
        if keys.contains(where: { $0.group != nil && $0.rotation != 0 }) { return (nil, [.complexGeometry]) }
        let defaults = keys.filter { $0.choice == nil || $0.choice == 0 }
        guard !defaults.isEmpty else { throw VIAImportError.invalidGeometry }
        let corners = defaults.flatMap(\.corners)
        let origin = (corners.map(\.0).min()!, corners.map(\.1).min()!)
        var selected = keys.filter { $0.group == nil }
        for group in options.indices {
            let grouped = keys.filter { $0.group == group }
            guard !grouped.isEmpty else { continue }
            let zero = grouped.filter { $0.choice == 0 }
            let chosen = grouped.filter { $0.choice == selection[group] }
            guard let zeroPivot = pivot(zero) else { throw VIAImportError.invalidGeometry }
            guard let chosenPivot = pivot(chosen) else { continue }
            // VIA and Vial align option groups differently when the leftmost key is below the top row.
            guard zeroPivot.x == zero.map(\.x).min(), chosenPivot.x == chosen.map(\.x).min() else {
                return (nil, [.complexGeometry])
            }
            selected += chosen.map { key in
                var moved = key
                moved.x -= chosenPivot.x - zeroPivot.x; moved.y -= chosenPivot.y - zeroPivot.y
                return moved
            }
        }
        return try geometry(selected, origin: origin)
    }

    private static func pivot(_ keys: [Key]) -> Key? {
        keys.min { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    static func compiled(_ layouts: [String: VIAJSONValue], rows: Int, cols: Int,
                         options: [VIALayoutOption], selection: [Int]?) throws -> Result {
        guard let common = layouts["keys"]?.array, let groups = layouts["optionKeys"]?.object,
              let width = layouts["width"]?.number, let height = layouts["height"]?.number,
              width.isFinite, height.isFinite, width > 0, height > 0 else { throw VIAImportError.invalidGeometry }
        var limitations: Set<VIAReferenceLimitation> = []
        if selection == nil || (!groups.isEmpty && options.isEmpty) { limitations.insert(.layoutOptions) }
        if !Set(layouts.keys).isSubset(of: ["keys", "optionKeys", "width", "height", "labels"]) { limitations.insert(.complexGeometry) }
        var all: [(VIAJSONValue, Bool)] = common.map { ($0, true) }
        for (groupText, group) in groups {
            guard let groupID = Int(groupText), groupID >= 0, String(groupID) == groupText,
                  let choices = group.object else { throw VIAImportError.invalidGeometry }
            if !options.isEmpty, !options.indices.contains(groupID) { throw VIAImportError.invalidGeometry }
            for (choiceText, choice) in choices {
                guard let choiceID = Int(choiceText), choiceID >= 0, String(choiceID) == choiceText,
                      let entries = choice.array else { throw VIAImportError.invalidGeometry }
                if options.indices.contains(groupID), !options[groupID].choices.indices.contains(choiceID) { throw VIAImportError.invalidGeometry }
                let active = selection?.indices.contains(groupID) == true && selection?[groupID] == choiceID
                all += entries.map { ($0, active) }
            }
        }
        guard !all.isEmpty else { throw VIAImportError.invalidGeometry }
        var selected: [Key] = []
        for (value, active) in all {
            guard let key = value.object, let row = key["row"]?.integer, let col = key["col"]?.integer,
                  (0..<rows).contains(row), (0..<cols).contains(col),
                  let x = key["x"]?.number, let y = key["y"]?.number,
                  let w = key["w"]?.number, let h = key["h"]?.number,
                  let r = key["r"]?.number, let rx = key["rx"]?.number, let ry = key["ry"]?.number,
                  [x, y, w, h, r, rx, ry].allSatisfy(\.isFinite), w > 0, h > 0,
                  let decal = key["d"], decal == .bool(false) || decal == .bool(true),
                  key["color"]?.string != nil else { throw VIAImportError.invalidGeometry }
            if !Set(key.keys).isSubset(of: ["row", "col", "x", "y", "w", "h", "r", "rx", "ry", "d", "color"]) || decal == .bool(true) {
                limitations.insert(.complexGeometry)
            }
            if active { selected.append(.init(row: row, column: col, x: x, y: y, width: w, height: h, rotation: r, rx: rx, ry: ry)) }
        }
        guard limitations.isEmpty else { return (nil, limitations) }
        return try geometry(selected, origin: (0, 0))
    }

    private static func geometry(_ keys: [Key], origin: (Double, Double)) throws -> Result {
        guard !keys.isEmpty else { throw VIAImportError.invalidGeometry }
        do { return (try CanonicalGeometry(positions: keys.map { try $0.position(origin: origin) }), []) }
        catch { throw VIAImportError.invalidGeometry }
    }
}
