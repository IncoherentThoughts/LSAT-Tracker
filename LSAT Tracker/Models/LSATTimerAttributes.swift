import Foundation
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
