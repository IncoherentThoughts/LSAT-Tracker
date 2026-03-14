import Foundation

/// Shared across the main app target and the widget extension target.
let appGroupSuite = "group.evan.lsattimer"

#if os(iOS)
import ActivityKit

struct LSATTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var dailyElapsed: TimeInterval
        var isRunning: Bool
        var timerStartedAt: Date?
        var dailyGoal: TimeInterval
    }
}
#endif
