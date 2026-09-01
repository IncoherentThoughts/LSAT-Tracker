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

    /// Desired end state. The widget buttons pass the state they were rendered
    /// for (!isRunning-as-displayed), which makes the tap idempotent: if the
    /// widget UI was stale and the timer is already where the user wants it,
    /// we refresh the widget instead of inverting the toggle. nil → plain toggle.
    @Parameter(title: "Set Running")
    var setRunning: Bool?

    init() {}

    init(setRunning: Bool) {
        self.setRunning = setRunning
    }

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: appGroupSuite)
        let isRunning = suite?.bool(forKey: "timerRunning") ?? false
        let goalRaw = suite?.double(forKey: "dailyGoal") ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400

        print("[ToggleIntent] fire — currently isRunning=\(isRunning), setRunning=\(String(describing: setRunning))")

        let newIsRunning: Bool
        let newStartedAt: Date?
        let newDailyElapsed: Double

        if setRunning == isRunning {
            // Already in the desired state — the button was rendered from a
            // stale snapshot. Don't mutate; push current truth so the widget
            // resnaps to reality.
            newIsRunning = isRunning
            newStartedAt = suite?.object(forKey: "timerStartedAt") as? Date
            newDailyElapsed = suite?.double(forKey: "dailyElapsed") ?? 0
        } else if isRunning {
            let stored = suite?.double(forKey: "dailyElapsed") ?? 0
            if let startedAt = suite?.object(forKey: "timerStartedAt") as? Date {
                let now = Date()
                let interval = max(0, now.timeIntervalSince(startedAt))
                let daily = stored + interval
                let total = (suite?.double(forKey: "totalElapsed") ?? 0) + interval
                suite?.set(daily, forKey: "dailyElapsed")
                suite?.set(total, forKey: "totalElapsed")
                // This bake has no 4am-boundary logic — the intent has no
                // TimerManager, only the shared suite. Leave the interval's
                // endpoints behind so the app's check4amBoundary() can
                // re-attribute the post-4am slice to the new day if this
                // pause spanned the boundary (e.g. Lock Screen pause at
                // 4:20am after running overnight).
                suite?.set(startedAt, forKey: "lastPausedStartedAt")
                suite?.set(now, forKey: "lastPausedAt")
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
            // A new running session obsoletes the last pause's breadcrumbs.
            suite?.removeObject(forKey: "lastPausedStartedAt")
            suite?.removeObject(forKey: "lastPausedAt")
            newIsRunning = true
            newStartedAt = startDate
            newDailyElapsed = suite?.double(forKey: "dailyElapsed") ?? 0
        }

        // `.updatable` includes `.stale` activities — still on screen, just
        // flagged old. They must be refreshed too, otherwise a pause tap on a
        // stale widget would do nothing and leave it showing the running
        // state. update() with a fresh staleDate also brings it back to .active.
        let updatable = Activity<LSATTimerAttributes>.updatable
        let allActivities = Activity<LSATTimerAttributes>.activities
        print("[ToggleIntent] updatable=\(updatable.count) total=\(allActivities.count) → newIsRunning=\(newIsRunning)")

        if newIsRunning {
            let runningState = LSATTimerAttributes.ContentState(
                dailyElapsed: newDailyElapsed,
                isRunning: true,
                timerStartedAt: newStartedAt,
                dailyGoal: dailyGoal
            )
            let staleAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
            let content = ActivityContent(state: runningState, staleDate: staleAt)
            // Resume: update in place when a card is on screen (smooth
            // crossfade), otherwise clear ended ghosts still riding out their
            // dismissal grace and request a fresh activity.
            if !updatable.isEmpty {
                for activity in updatable {
                    await activity.update(content)
                }
            } else {
                for ghost in allActivities {
                    await ghost.end(nil, dismissalPolicy: .immediate)
                }
                let authInfo = ActivityAuthorizationInfo()
                if authInfo.areActivitiesEnabled {
                    do {
                        _ = try Activity<LSATTimerAttributes>.request(
                            attributes: LSATTimerAttributes(),
                            content: content
                        )
                    } catch {
                        print("[ToggleIntent] request failed: \(error)")
                    }
                }
            }
        } else {
            // Pause: end with the paused state as final content and a grace
            // dismissal. The SYSTEM removes the card liveActivityIdleTimeout
            // from now — no app wakeup needed, so nothing lingers after a
            // force-quit or reboot. An update() here would leave the card
            // .active forever (nothing else runs to end it). isEnded=true
            // drops the play button: the ended card is a frozen snapshot.
            let finalState = LSATTimerAttributes.ContentState(
                dailyElapsed: newDailyElapsed,
                isRunning: false,
                timerStartedAt: nil,
                dailyGoal: dailyGoal,
                isEnded: true
            )
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            let dismissAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
            for activity in allActivities {
                await activity.end(finalContent, dismissalPolicy: .after(dismissAt))
            }
        }

        // Tell the running app to adopt the state we just wrote, so its
        // in-memory TimerManager and on-screen timer don't diverge from the
        // widget. Delivered to all processes — including the app's own when it
        // is foregrounded (e.g. a Dynamic Island tap while using the app).
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(timerStateChangedNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
#endif
