import Foundation

public enum ReplayWorkload {
    public static let fixtureJSON = Data("[[0,1,2,3,0,1,2,3],[0],[1],[2],[3],[0],[1],[2],[3],[0]]".utf8)
    public static let activeTicks = 1_500
    public static let windowTicks = 1_520
    public static let tickIntervalSeconds = 0.1
    public static let warmupSeconds = 30.0
    public static let measureSeconds = 120.0
    public static let repeats = 1

    public static let expectedTypingEvents: Int = {
        let keyCounts = [8, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        return (0..<activeTicks).reduce(0) { total, tick in
            total + keyCounts[tick % keyCounts.count] * 2
        }
    }()
}
