import Foundation
import Observation
#if os(iOS)
import ActivityKit
#endif

// MARK: - Shared UserDefaults keys
private enum TimerKey {
    static let dailyElapsed  = "dailyElapsed"
    static let totalElapsed  = "totalElapsed"
    static let lastResetDate = "lastResetDate"
    static let timerRunning  = "timerRunning"
    static let timerStartedAt = "timerStartedAt"
    static let dailyGoal     = "dailyGoal"
    // Written by ToggleTimerIntent on a Lock Screen pause: the endpoints of
    // the interval it baked into dailyElapsed without boundary logic, so
    // check4amBoundary() can split that interval retroactively.
    static let lastPausedStartedAt = "lastPausedStartedAt"
    static let lastPausedAt  = "lastPausedAt"
}

@Observable
final class TimerManager {
    // MARK: - Observed state (drives UI)
    private(set) var dailyElapsed: TimeInterval = 0
    private(set) var totalElapsed: TimeInterval = 0
    private(set) var isRunning: Bool = false
    private(set) var tick: Int = 0

    // MARK: - Session persistence hook
    /// Called at critical points (pause, background, 4am boundary) so the
    /// StudyStore can write a StudySession record. Set by LSAT_TrackerApp.
    var persistSession: ((Date, TimeInterval) -> Void)?

    // MARK: - Private
    private var timerStartedAt: Date?
    private var displayTimer: Timer?
    private let suite: UserDefaults
    #if os(iOS)
    private var liveActivity: Activity<LSATTimerAttributes>?
    /// Tail of a FIFO chain that serializes EVERY Live Activity mutation
    /// (update, end, request). Rapid pause→resume→pause otherwise interleaves:
    /// an in-flight request() can land after a later end() enumerated the
    /// activity list, resurrecting a ticking RUNNING card that nothing is
    /// scheduled to remove. Ops must also enumerate Activity.activities
    /// INSIDE their queued block — a snapshot taken at enqueue time can miss
    /// a card the prior op is about to create.
    private var activityPipeline: Task<Void, Never>?

    private func enqueueActivityOp(_ op: @escaping () async -> Void) {
        let prior = activityPipeline
        activityPipeline = Task {
            await prior?.value
            await op()
        }
    }
    #endif

    // MARK: - Init
    init() {
        suite = UserDefaults(suiteName: appGroupSuite) ?? .standard
        rehydrate()
        registerForStateChanges()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Computed display values (add live interval if running)
    var computedDaily: TimeInterval {
        _ = tick
        guard isRunning, let start = timerStartedAt else { return dailyElapsed }
        return dailyElapsed + max(0, Date().timeIntervalSince(start))
    }

    var computedTotal: TimeInterval {
        _ = tick
        guard isRunning, let start = timerStartedAt else { return totalElapsed }
        return totalElapsed + max(0, Date().timeIntervalSince(start))
    }

    // MARK: - Lifecycle

    /// Call on app background/inactive while timer is running.
    /// Snapshots computed elapsed into UserDefaults and resets the reference
    /// point to now — prevents double-counting on the next foreground rehydrate.
    func onBackground() {
        guard isRunning else { return }
        // The app can stay foregrounded across 4am (macOS window left open,
        // iOS with auto-lock off), in which case onForeground's boundary
        // check is stale. Roll the boundary first — it re-anchors
        // timerStartedAt to 4am — so the snapshot below bakes only
        // post-boundary time into the new day.
        check4amBoundary()
        let now = Date()
        let snapshotDaily = computedDaily
        let snapshotTotal = computedTotal
        // Advance the stored base values to the current moment
        dailyElapsed = snapshotDaily
        totalElapsed = snapshotTotal
        // Move the reference point forward so rehydrate sees no elapsed gap
        timerStartedAt = now
        suite.set(snapshotDaily, forKey: TimerKey.dailyElapsed)
        suite.set(snapshotTotal, forKey: TimerKey.totalElapsed)
        suite.set(now, forKey: TimerKey.timerStartedAt)
        persistCurrentDaySession()
    }

    /// Call on every app foreground: check 4am boundary + rehydrate
    func onForeground() {
        check4amBoundary()
        rehydrate()
        stopDisplayTimer()
        if isRunning {
            startDisplayTimer()
        }
        persistCurrentDaySession()
        #if os(iOS)
        // Reconcile the Lock Screen with the timer state. Activities outlive
        // the app process (force-quit and even reboot), so in-memory state
        // proves nothing — enumerate what actually exists every time.
        if isRunning {
            // Refresh content on any on-screen activity — including .stale
            // ones, which update() restores to .active. Smooth, no flicker.
            // Don't recreate ended activities — the user's already in the app.
            let content = contentForCurrentState()
            enqueueActivityOp {
                let updatable = Activity<LSATTimerAttributes>.updatable
                guard let first = updatable.first else { return }
                self.liveActivity = first
                for activity in updatable {
                    await activity.update(content)
                }
            }
        } else if !Activity<LSATTimerAttributes>.updatable.isEmpty {
            // Timer is paused but a live (.active/.stale) card is still up —
            // an orphan from an older build, a crash, or a missed end(). A
            // paused card should only ever exist as an *ended* one riding out
            // its dismissal grace, so kill these outright. This is also what
            // clears cards stuck on screen from before this fix shipped.
            endLiveActivity()
        }
        #endif
    }

    // MARK: - Cross-process sync (Live Activity intent → app)

    /// Subscribe to the Darwin notification `ToggleTimerIntent` posts after it
    /// writes new state to the shared suite. The C callback can't capture
    /// `self`, so we hand it an unretained opaque pointer and recover the
    /// instance inside. Delivered on the main run loop; we hop to main anyway
    /// to be safe before touching observed state.
    private func registerForStateChanges() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let manager = Unmanaged<TimerManager>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { manager.reconcileFromSharedState() }
            },
            timerStateChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Adopt state the Live Activity intent just wrote to the shared suite.
    /// Pure read + local display-timer sync — it must NOT write back to the
    /// suite or push a Live Activity update, since the intent is the canonical
    /// writer here and already did both. Writing back would clobber the
    /// intent's values and could ping-pong.
    func reconcileFromSharedState() {
        rehydrate()
        stopDisplayTimer()
        if isRunning {
            startDisplayTimer()
        }
        // Nudge computed values so the UI reflects the new baseline at once.
        tick += 1
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        let startDate = Date()
        timerStartedAt = startDate
        isRunning = true
        suite.set(dailyElapsed, forKey: TimerKey.dailyElapsed)
        suite.set(totalElapsed, forKey: TimerKey.totalElapsed)
        suite.set(true, forKey: TimerKey.timerRunning)
        suite.set(startDate, forKey: TimerKey.timerStartedAt)
        // A new running session obsoletes the last pause's breadcrumbs.
        suite.removeObject(forKey: TimerKey.lastPausedStartedAt)
        suite.removeObject(forKey: TimerKey.lastPausedAt)
        startDisplayTimer()
        #if os(iOS)
        presentRunningActivity()
        #endif
    }

    /// `endingLiveActivity: false` is for the resets, which end the activity
    /// themselves with .immediate right after — skipping the grace-end here
    /// avoids two racing end() calls with different dismissal policies.
    func pause(endingLiveActivity: Bool = true) {
        guard isRunning else { return }
        // Same foregrounded-across-4am hazard as onBackground(): roll the
        // boundary first so the interval baked below never spans it.
        check4amBoundary()
        let interval = timerStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        dailyElapsed += interval
        totalElapsed += interval
        timerStartedAt = nil
        isRunning = false
        stopDisplayTimer()
        persistState()
        persistCurrentDaySession()
        #if os(iOS)
        // End with the paused state as final content and a grace-period
        // dismissal. end() still crossfades the card to the paused content,
        // and the system removes it after the grace even if the app never
        // runs again — an update() here would leave the card .active with
        // nothing ever ending it (Lock Screen ghost for up to 12 hours).
        if endingLiveActivity {
            endLiveActivityAfterGrace()
        }
        #endif
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    // MARK: - Resets

    func resetDaily() {
        let wasRunning = isRunning
        if wasRunning { pause(endingLiveActivity: false) }
        dailyElapsed = 0
        suite.set(0.0, forKey: TimerKey.dailyElapsed)
        #if os(iOS)
        endLiveActivity()
        #endif
        if wasRunning { start() }
    }

    func resetTotal() {
        let wasRunning = isRunning
        if wasRunning { pause(endingLiveActivity: false) }
        dailyElapsed = 0
        totalElapsed = 0
        suite.set(0.0, forKey: TimerKey.dailyElapsed)
        suite.set(0.0, forKey: TimerKey.totalElapsed)
        #if os(iOS)
        endLiveActivity()
        #endif
        if wasRunning { start() }
    }

    // MARK: - Manual edit support

    /// Apply a manual duration override for a specific date.
    /// For today: adjusts dailyElapsed and totalElapsed, resets live-counting origin if running.
    /// For past dates: applies the delta (new - old) to totalElapsed.
    func applyManualEdit(date: Date, duration: TimeInterval, previousDuration: TimeInterval = 0) {
        let today = Calendar.current.startOfDay(for: Date())
        let editDay = Calendar.current.startOfDay(for: date)
        if editDay == today {
            let delta = duration - dailyElapsed
            dailyElapsed = duration
            // Reset the live-counting reference point so computedDaily doesn't double-count
            if isRunning { timerStartedAt = Date() }
            totalElapsed = max(0, totalElapsed + delta)
        } else {
            // Adjust total by the difference between old and new duration for past dates
            let delta = duration - previousDuration
            totalElapsed = max(0, totalElapsed + delta)
        }
        persistState()
    }

    // MARK: - Private helpers

    private func rehydrate() {
        dailyElapsed = suite.double(forKey: TimerKey.dailyElapsed)
        totalElapsed = suite.double(forKey: TimerKey.totalElapsed)
        isRunning = suite.bool(forKey: TimerKey.timerRunning)
        timerStartedAt = suite.object(forKey: TimerKey.timerStartedAt) as? Date
    }

    /// Calendar date (startOfDay) that the current `dailyElapsed` should be
    /// recorded under. The timer's "day" runs from 4am to 4am, so the correct
    /// calendar date is startOfDay(lastResetDate) when available, otherwise
    /// the most recent 4am anchor before now.
    private func currentStudyDayDate() -> Date {
        let cal = Calendar.current
        if let lastReset = suite.object(forKey: TimerKey.lastResetDate) as? Date,
           lastReset > .distantPast {
            return cal.startOfDay(for: lastReset)
        }
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 4
        comps.minute = 0
        comps.second = 0
        let today4am = cal.date(from: comps) ?? now
        let anchor = now < today4am ? today4am.addingTimeInterval(-86400) : today4am
        return cal.startOfDay(for: anchor)
    }

    private func persistCurrentDaySession() {
        let duration = computedDaily
        guard duration > 0 else { return }
        persistSession?(currentStudyDayDate(), duration)
    }

    private func persistState() {
        suite.set(dailyElapsed, forKey: TimerKey.dailyElapsed)
        suite.set(totalElapsed, forKey: TimerKey.totalElapsed)
        suite.set(isRunning, forKey: TimerKey.timerRunning)
        if let startDate = timerStartedAt {
            suite.set(startDate, forKey: TimerKey.timerStartedAt)
        } else {
            suite.removeObject(forKey: TimerKey.timerStartedAt)
        }
    }

    private func check4amBoundary() {
        let calendar = Calendar.current
        let now = Date()
        let lastReset = suite.object(forKey: TimerKey.lastResetDate) as? Date ?? .distantPast

        // Find the most recent 4am boundary before now
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 4
        components.minute = 0
        components.second = 0
        guard let todayAt4am = calendar.date(from: components) else { return }
        let boundary = now < todayAt4am
            ? todayAt4am.addingTimeInterval(-86400)
            : todayAt4am

        guard lastReset < boundary else { return }

        // totalElapsed is always kept in sync with dailyElapsed via pause() and onBackground(),
        // so it already includes dailyElapsed — do NOT add dailyElapsed again.
        //
        // For a running timer we need to adjust for in-flight time relative to the boundary:
        //   • timerStartedAt < boundary: totalElapsed doesn't yet include time from startedAt
        //     to boundary → add that pre-boundary slice.
        //   • timerStartedAt > boundary: onBackground() already baked post-boundary time into
        //     totalElapsed that belongs to the new day → subtract it back out.
        let wasRunning = suite.bool(forKey: TimerKey.timerRunning)
        var preBoundaryElapsed: TimeInterval = 0
        var postBoundaryInTotal: TimeInterval = 0
        if wasRunning,
           let startedAt = suite.object(forKey: TimerKey.timerStartedAt) as? Date {
            if startedAt < boundary {
                preBoundaryElapsed = max(0, boundary.timeIntervalSince(startedAt))
            } else {
                postBoundaryInTotal = max(0, startedAt.timeIntervalSince(boundary))
            }
        }

        let savedTotal = suite.double(forKey: TimerKey.totalElapsed)
        let newTotal = savedTotal - postBoundaryInTotal + preBoundaryElapsed

        // Persist the departing day's session before zeroing. `dailyElapsed` in
        // UserDefaults represents accumulated study for the day that *started*
        // at lastReset's 4am anchor; add the pre-boundary in-flight slice if
        // the timer was running across the boundary.
        let savedDaily = suite.double(forKey: TimerKey.dailyElapsed)

        // A Lock Screen pause (ToggleTimerIntent) bakes its full running
        // interval into dailyElapsed with no boundary logic, leaving the
        // interval's endpoints in lastPausedStartedAt/lastPausedAt. If that
        // interval straddled the boundary, the post-boundary slice belongs to
        // the NEW day: carve it out of the ended day's credit and seed the new
        // day's dailyElapsed with it. totalElapsed needs no adjustment — the
        // intent baked both slices there, and both belong in the all-time sum.
        var carryIntoNewDay: TimeInterval = 0
        if !wasRunning,
           let pausedStart = suite.object(forKey: TimerKey.lastPausedStartedAt) as? Date,
           let pausedAt = suite.object(forKey: TimerKey.lastPausedAt) as? Date,
           pausedStart < boundary, pausedAt > boundary {
            carryIntoNewDay = min(max(0, pausedAt.timeIntervalSince(boundary)), savedDaily)
        }

        let endedDayDuration = savedDaily + preBoundaryElapsed - carryIntoNewDay
        if endedDayDuration > 0, lastReset > .distantPast {
            let endedDay = calendar.startOfDay(for: lastReset)
            persistSession?(endedDay, endedDayDuration)
        }

        suite.set(carryIntoNewDay, forKey: TimerKey.dailyElapsed)
        suite.set(newTotal, forKey: TimerKey.totalElapsed)
        suite.set(now, forKey: TimerKey.lastResetDate)
        // Consumed by this roll — or obsoleted by it, if the pause didn't span
        // the boundary just processed.
        suite.removeObject(forKey: TimerKey.lastPausedStartedAt)
        suite.removeObject(forKey: TimerKey.lastPausedAt)

        dailyElapsed = carryIntoNewDay
        totalElapsed = newTotal

        // Re-anchor timerStartedAt to the boundary so computedDaily only counts
        // post-boundary time. rehydrate() runs immediately after and reads this.
        if wasRunning {
            suite.set(boundary, forKey: TimerKey.timerStartedAt)
            timerStartedAt = boundary
        }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick += 1
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Live Activity management

    #if os(iOS)
    private var currentDailyGoal: TimeInterval {
        let g = suite.double(forKey: TimerKey.dailyGoal)
        return g > 0 ? g : 14400
    }

    private func makeContentState() -> LSATTimerAttributes.ContentState {
        LSATTimerAttributes.ContentState(
            dailyElapsed: dailyElapsed,
            isRunning: isRunning,
            timerStartedAt: timerStartedAt,
            dailyGoal: currentDailyGoal
        )
    }

    private func contentForCurrentState() -> ActivityContent<LSATTimerAttributes.ContentState> {
        let staleAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        return ActivityContent(state: makeContentState(), staleDate: staleAt)
    }

    /// Bring the Live Activity to a running .active state. Updates an existing
    /// on-screen activity in place — .active or .stale, since update() restores
    /// a stale one to .active with a fresh staleDate (smooth crossfade, no
    /// end-and-recreate flicker) — or requests a fresh one if none exists.
    /// Runs on the pipeline so any in-flight end() (pause grace-end, reset
    /// immediate-end) settles before the update-vs-request decision — and so
    /// a pause landing right after this one waits for the request() to finish
    /// and can end the card it created.
    private func presentRunningActivity() {
        let content = contentForCurrentState()
        enqueueActivityOp {
            let updatable = Activity<LSATTimerAttributes>.updatable
            if let first = updatable.first {
                self.liveActivity = first
                for activity in updatable {
                    await activity.update(content)
                }
                return
            }
            // Nothing on screen — clear ended ghosts still riding out their
            // dismissal grace so we don't stack a new card on top of one.
            for ghost in Activity<LSATTimerAttributes>.activities {
                await ghost.end(nil, dismissalPolicy: .immediate)
            }
            let authInfo = ActivityAuthorizationInfo()
            guard authInfo.areActivitiesEnabled else {
                print("[LiveActivity] Blocked: Live Activities disabled.")
                return
            }
            do {
                self.liveActivity = try Activity<LSATTimerAttributes>.request(
                    attributes: LSATTimerAttributes(),
                    content: content
                )
                print("[LiveActivity] Started")
            } catch {
                print("[LiveActivity] request failed: \(error)")
            }
        }
    }

    /// End every Live Activity with the paused state as final content, letting
    /// the SYSTEM remove it `liveActivityIdleTimeout` after the pause. The
    /// scheduled dismissal doesn't need the app to run again, so the card is
    /// guaranteed off the Lock Screen even after a force-quit or reboot.
    /// isEnded=true makes the widget render a static card (no play button —
    /// an ended activity is a frozen snapshot that intents can't re-render).
    private func endLiveActivityAfterGrace() {
        let finalState = LSATTimerAttributes.ContentState(
            dailyElapsed: dailyElapsed,
            isRunning: false,
            timerStartedAt: nil,
            dailyGoal: currentDailyGoal,
            isEnded: true
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        let dismissAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        liveActivity = nil
        enqueueActivityOp {
            for activity in Activity<LSATTimerAttributes>.activities {
                await activity.end(content, dismissalPolicy: .after(dismissAt))
            }
        }
    }

    /// End every Live Activity immediately — not just the one held in
    /// `liveActivity`: an activity started from the Lock Screen (via the
    /// intent) is owned by a different launch and won't be in our stored
    /// reference, so relying on it would orphan the widget on a daily/total
    /// reset.
    private func endLiveActivity() {
        let finalState = LSATTimerAttributes.ContentState(
            dailyElapsed: 0, isRunning: false, timerStartedAt: nil,
            dailyGoal: currentDailyGoal, isEnded: true
        )
        let content = ActivityContent(state: finalState, staleDate: .now)
        liveActivity = nil
        enqueueActivityOp {
            for activity in Activity<LSATTimerAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
    #endif
}

// MARK: - TimeInterval formatting
extension TimeInterval {
    /// HH:MM:SS format
    var timerFormatted: String {
        let total = Int(max(0, self))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// H:MM format for compact display
    var compactFormatted: String {
        let total = Int(max(0, self))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}
