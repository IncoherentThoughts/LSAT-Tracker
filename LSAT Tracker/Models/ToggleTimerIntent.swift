import Foundation

#if os(iOS)
import ActivityKit
import AppIntents

/// Lives in both the main app target and the widget extension target (via
/// project.pbxproj membership exceptions). LiveActivityIntents fired from a
/// Live Activity button are dispatched by iOS through the app's process, so
/// the intent class must be visible to the main app — not only the widget.
struct ToggleTimerIntent: LiveActivityIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Toggle LSAT Timer"
    static var description = IntentDescription("Starts or pauses the LSAT study timer.")

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: appGroupSuite)
        let isRunning = suite?.bool(forKey: "timerRunning") ?? false
        let goalRaw = suite?.double(forKey: "dailyGoal") ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400

        print("[ToggleIntent] fire — currently isRunning=\(isRunning)")

        let newIsRunning: Bool
        let newStartedAt: Date?
        let newDailyElapsed: Double

        if isRunning {
            let stored = suite?.double(forKey: "dailyElapsed") ?? 0
            if let startedAt = suite?.object(forKey: "timerStartedAt") as? Date {
                let interval = max(0, Date().timeIntervalSince(startedAt))
                let daily = stored + interval
                let total = (suite?.double(forKey: "totalElapsed") ?? 0) + interval
                suite?.set(daily, forKey: "dailyElapsed")
                suite?.set(total, forKey: "totalElapsed")
                suite?.removeObject(forKey: "timerStartedAt")
                newDailyElapsed = daily
            } else {
                newDailyElapsed = stored
            }
            suite?.set(false, forKey: "timerRunning")
            newIsRunning = false
            newStartedAt = nil
        } else {
            let startDate = Date()
            suite?.set(startDate, forKey: "timerStartedAt")
            suite?.set(true, forKey: "timerRunning")
            newIsRunning = true
            newStartedAt = startDate
            newDailyElapsed = suite?.double(forKey: "dailyElapsed") ?? 0
        }

        let newState = LSATTimerAttributes.ContentState(
            dailyElapsed: newDailyElapsed,
            isRunning: newIsRunning,
            timerStartedAt: newStartedAt,
            dailyGoal: dailyGoal
        )
        let content = ActivityContent(
            state: newState,
            staleDate: .now.addingTimeInterval(8 * 3600)
        )

        let activities = Activity<LSATTimerAttributes>.activities
        print("[ToggleIntent] pushing update to \(activities.count) activity(ies) → isRunning=\(newIsRunning)")
        for activity in activities {
            await activity.update(content)
        }
        return .result()
    }
}
#endif
