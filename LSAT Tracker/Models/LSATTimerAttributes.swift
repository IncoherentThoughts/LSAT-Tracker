import Foundation

/// Shared across the main app target and the widget extension target.
let appGroupSuite = "group.evan.lsattimer"

/// Grace period for the Live Activity after a pause. Pausing ends the
/// activity with `end(_, dismissalPolicy: .after(now + this))`, so the paused
/// card stays readable this long and then the SYSTEM removes it — no app
/// wakeup needed, which is what guarantees cleanup after force-quit/reboot.
/// (A staleDate can't do this: it only marks the card .stale, never removes
/// it, and an un-ended activity otherwise sits on the Lock Screen for up to
/// 12 hours.) Must stay ≤ 4 hours — iOS clamps .after() to end + 4h.
/// Shared so the app and widget intent agree.
let liveActivityIdleTimeout: TimeInterval = 30 * 60

/// Darwin notification name posted by `ToggleTimerIntent` after it mutates the
/// shared timer state from a Live Activity button. The running app observes it
/// (`CFNotificationCenterGetDarwinNotifyCenter`) and reconciles its in-memory
/// `TimerManager` immediately — without this bridge the app only re-reads the
/// shared suite on foreground, so widget toggles silently diverge while the app
/// is open. Plain CFString name; carries no payload (state lives in the suite).
let timerStateChangedNotification = "group.evan.lsattimer.stateChanged"

#if os(iOS)
import ActivityKit

struct LSATTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var dailyElapsed: TimeInterval
        var isRunning: Bool
        var timerStartedAt: Date?
        var dailyGoal: TimeInterval
        /// True only on the final content passed to end(). An ended card is a
        /// frozen snapshot — intents can't re-render it — so the view must
        /// drop the play/pause button and show a static "paused" treatment.
        /// Optional so payloads persisted by older builds still decode.
        var isEnded: Bool? = nil
    }
}

extension Activity where Attributes == LSATTimerAttributes {
    /// Activities still on screen that update() can refresh. A .stale activity
    /// is visually present (just past its staleDate), so it must be updated
    /// like an .active one — skipping it desyncs the Lock Screen from the app.
    /// nonisolated: read from both the main actor (TimerManager) and the
    /// intent's nonisolated perform().
    nonisolated static var updatable: [Activity<LSATTimerAttributes>] {
        activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }
}
#endif
