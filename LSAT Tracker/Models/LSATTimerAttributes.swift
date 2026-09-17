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

// MARK: - Shared UserDefaults keys

/// Every key written to the app-group suite, in one place.
///
/// These are read by three separate processes — the app, the widget extension,
/// and the intents the system dispatches from the Lock Screen — so the names
/// live here rather than being duplicated per process. The suite is the local
/// cache of the Clock State (see `ClockSnapshot`).
///
/// There is deliberately no `totalElapsed`: the All-Time Total is derived from
/// the Sessions (`pastTotal` + today's Clock), never stored as its own running
/// counter that could drift away from the history it claims to summarise.
nonisolated enum TimerKey {
    static let dailyElapsed     = "dailyElapsed"
    static let timerRunning     = "timerRunning"
    static let timerStartedAt   = "timerStartedAt"
    static let dailyGoal        = "dailyGoal"
    static let studyDay         = "studyDay"
    static let lastActionAt     = "lastActionAt"
    static let lastActionDevice = "lastActionDevice"
    static let deviceID         = "deviceID"
    static let pendingSessions  = "pendingSessions"

    /// Sum of every Session before the current Study Day, cached by the app
    /// so the widgets and intents can show an All-Time Total without SwiftData.
    static let pastTotal        = "pastTotal"

    /// Written by the running Mac app every minute while the Clock is
    /// running and on every Clock Action. The widget shows its stale hint
    /// when the Clock is running but this is older than three minutes,
    /// which means the app that would keep the widget current has quit.
    static let appHeartbeat     = "appHeartbeat"

    /// Pre-sync installs kept the Study Day here; read once for migration by
    /// `ClockSnapshot(suite:)`, then superseded by `studyDay`.
    static let legacyLastResetDate = "lastResetDate"

    /// Keys the pre-snapshot build wrote that nothing reads any more. Cleared
    /// once on launch so a stale `totalElapsed` cannot be mistaken for truth
    /// by anything (including a future reader) after the total became derived.
    static let retired: [String] = [
        "totalElapsed",
        "lastPausedStartedAt",
        "lastPausedAt",
        "totalRecalibratedV2",
    ]
}

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

nonisolated extension ClockSnapshot {
    /// What the Live Activity needs to render this Clock State.
    var liveActivityState: LSATTimerAttributes.ContentState {
        LSATTimerAttributes.ContentState(
            dailyElapsed: dailyBase,
            isRunning: isRunning,
            timerStartedAt: runStartedAt,
            dailyGoal: dailyGoal
        )
    }

    /// The frozen final content for an ended card: paused, no play button.
    var endedLiveActivityState: LSATTimerAttributes.ContentState {
        LSATTimerAttributes.ContentState(
            dailyElapsed: daily(at: Date()),
            isRunning: false,
            timerStartedAt: nil,
            dailyGoal: dailyGoal,
            isEnded: true
        )
    }
}
#endif
