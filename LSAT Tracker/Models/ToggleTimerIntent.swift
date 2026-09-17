import Foundation
import AppIntents
#if os(iOS)
import ActivityKit
/// `LiveActivityIntent` (iOS) lets the system run the intent in-process from
/// a Live Activity button; on macOS a plain `AppIntent` serves widgets and
/// Control Center the same way.
typealias ClockIntent = LiveActivityIntent
#else
typealias ClockIntent = AppIntent
#endif

/// Lives in both the main app target and the widget extension target (via
/// project.pbxproj membership exceptions). LiveActivityIntents fired from a
/// Live Activity button are dispatched by iOS through the app's process, so
/// the intent class must be visible to the main app — not only the widget.
///
/// It performs the same Clock Actions as `TimerManager`, through the same
/// `ClockSnapshot` methods, so a Lock Screen tap and an in-app tap bank time
/// identically. The Rollover runs first and any departing day is queued for
/// the app to persist — an intent cannot reach SwiftData.
struct ToggleTimerIntent: ClockIntent {
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
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        let now = Date()
        let device = ClockSnapshot.deviceID(in: suite)

        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }

        // `setRunning == isRunning` means the button was rendered from a stale
        // snapshot and the Clock is already where the user wants it. Don't
        // mutate; just push current truth so the card resnaps to reality.
        if setRunning != snap.isRunning {
            if snap.isRunning {
                snap.pause(at: now, device: device)
            } else {
                snap.start(at: now, device: device)
            }
        }
        snap.write(to: suite)

        await presentLiveActivity(for: snap, allowRequest: snap.isRunning)
        notifyApp()
        return .result()
    }
}

// MARK: - Live Activity helpers shared by the intents

#if os(iOS)
/// Push `snap` to the Lock Screen.
///
/// Running: refresh every on-screen activity — a `.stale` one is still
/// visible, just flagged old, and update() with a fresh staleDate brings it
/// back to .active — or request a fresh card when nothing is up and
/// `allowRequest` is set.
///
/// Paused: END the activities with the paused state as final content and a
/// grace dismissal. The SYSTEM removes the card `liveActivityIdleTimeout` from
/// now with no app wakeup, so nothing lingers after a force-quit or reboot. An
/// update() here would leave the card .active forever, since nothing else runs
/// to end it. isEnded=true drops the play button: an ended card is a frozen
/// snapshot that intents cannot re-render.
func presentLiveActivity(for snap: ClockSnapshot, allowRequest: Bool) async {
    let activities = Activity<LSATTimerAttributes>.activities
    let updatable = Activity<LSATTimerAttributes>.updatable

    guard snap.isRunning else {
        let finalContent = ActivityContent(state: snap.endedLiveActivityState, staleDate: nil)
        let dismissAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        for activity in activities {
            await activity.end(finalContent, dismissalPolicy: .after(dismissAt))
        }
        return
    }

    let content = ActivityContent(
        state: snap.liveActivityState,
        staleDate: Date.now.addingTimeInterval(liveActivityIdleTimeout)
    )
    if !updatable.isEmpty {
        for activity in updatable {
            await activity.update(content)
        }
    } else if allowRequest {
        // Clear ended ghosts still riding out their dismissal grace so we
        // don't stack a new card on top of one.
        for ghost in activities {
            await ghost.end(nil, dismissalPolicy: .immediate)
        }
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity<LSATTimerAttributes>.request(
                    attributes: LSATTimerAttributes(),
                    content: content
                )
            } catch {
                print("[Intent] Live Activity request failed: \(error)")
            }
        }
    }
}

#else
/// No Live Activity on macOS; the Menu Bar Item and widget re-read the suite.
func presentLiveActivity(for snap: ClockSnapshot, allowRequest: Bool) async {}
#endif

/// Tell the running app to adopt the state just written to the suite, so its
/// in-memory `TimerManager` does not diverge from the widget. Delivered to all
/// processes, including the app's own when it is foregrounded.
func notifyApp() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(timerStateChangedNotification as CFString),
        nil,
        nil,
        true
    )
}
