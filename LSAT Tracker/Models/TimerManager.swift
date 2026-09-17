import Foundation
import Observation
#if os(iOS)
import ActivityKit
#endif

/// Owns the in-memory Clock State and performs every Clock Action.
///
/// The state itself is a `ClockSnapshot`. After each action the manager writes
/// it to the app-group suite (for intents and widgets), persists today's
/// Session, and hands the snapshot to `onStateChanged` so a later sync layer
/// can upload it.
///
/// All-time figures are derived: `pastTotal` is the cached sum of every
/// Session before the current Study Day, refreshed by `StudyStore`. There is
/// no stored all-time counter — the Sessions are the history, and the total is
/// always a function of them.
@Observable
final class TimerManager {
    // MARK: - Observed state (drives UI)
    private(set) var snapshot: ClockSnapshot
    private(set) var tick: Int = 0
    private(set) var pastTotal: TimeInterval = 0

    var isRunning: Bool { snapshot.isRunning }
    var studyDay: Date { snapshot.studyDay }
    var dailyGoal: TimeInterval { snapshot.dailyGoal }
    var dailyGoalHours: Int { max(1, Int(snapshot.dailyGoal / 3600)) }

    // MARK: - Hooks (set by LSAT_TrackerApp once the store exists)

    /// Writes a Session for a Study Day. Departing days are queued in the suite
    /// until this is set, then drained.
    var persistSession: ((Date, TimeInterval) -> Void)? {
        didSet { drainPendingSessions() }
    }

    /// Called after every Clock Action with the new state.
    var onStateChanged: ((ClockSnapshot) -> Void)?

    // MARK: - Private
    private var displayTimer: Timer?
    private let suite: UserDefaults
    private let deviceID: String
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
        deviceID = ClockSnapshot.deviceID(in: suite)
        snapshot = ClockSnapshot(suite: suite)
        pastTotal = suite.double(forKey: TimerKey.pastTotal)
        // The pre-snapshot build's keys are dead weight now, and a lingering
        // `totalElapsed` is actively misleading once the total is derived.
        for key in TimerKey.retired { suite.removeObject(forKey: key) }
        performRolloverIfNeeded()
        snapshot.write(to: suite)
        if snapshot.isRunning { startDisplayTimer() }
        registerForStateChanges()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Computed display values

    var computedDaily: TimeInterval {
        _ = tick
        return snapshot.daily(at: Date())
    }

    var computedTotal: TimeInterval {
        pastTotal + computedDaily
    }

    // MARK: - Lifecycle

    /// Call on app background/inactive. Nothing to bank — displayed time is
    /// always base plus in-flight — but the day and today's Session should be
    /// current before the process is suspended.
    func onBackground() {
        performRolloverIfNeeded()
        snapshot.write(to: suite)
        persistCurrentDaySession()
    }

    /// Call on every app foreground: adopt anything the intents wrote, roll
    /// over if needed, and reconcile the Lock Screen.
    func onForeground() {
        reconcileFromSharedState()
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
            // its dismissal grace, so kill these outright.
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

    /// Adopt the state in the shared suite (written by an intent or by this
    /// app earlier), merge it with what we hold, and bring the day up to date.
    func reconcileFromSharedState() {
        adopt(ClockSnapshot(suite: suite), notify: true)
    }

    /// Merge `incoming` (from the suite, or later from a synced record) with
    /// the current state by the last-action-wins rule, then bring the day up to
    /// date. `notify` decides whether the merged state is pushed back out;
    /// false when the state came from there.
    ///
    /// This deliberately does NOT touch the Live Activity. The intent is the
    /// canonical writer for anything arriving here from the Lock Screen and has
    /// already updated or ended the card; pushing another update would clobber
    /// its values and could ping-pong. `onForeground()` owns reconciliation of
    /// the card itself.
    func adopt(_ incoming: ClockSnapshot, notify: Bool) {
        let merged = ClockSnapshot.merged(local: snapshot, remote: incoming)
        let changed = merged != snapshot
        snapshot = merged
        let rolled = performRolloverIfNeeded()
        snapshot.write(to: suite)
        drainPendingSessions()
        syncDisplayTimer()
        persistCurrentDaySession()
        tick += 1
        if (changed || rolled) && notify {
            onStateChanged?(snapshot)
        }
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        performRolloverIfNeeded()
        snapshot.start(at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        presentRunningActivity()
        #endif
    }

    /// `endingLiveActivity: false` is for the resets and the backup restore,
    /// which end the activity themselves with .immediate right after —
    /// skipping the grace-end here avoids two racing end() calls with
    /// different dismissal policies.
    func pause(endingLiveActivity: Bool = true) {
        guard isRunning else { return }
        performRolloverIfNeeded()
        snapshot.pause(at: Date(), device: deviceID)
        commit()
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

    func setDailyGoal(hours: Int) {
        snapshot.setDailyGoal(TimeInterval(hours) * 3600, at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    // MARK: - Resets

    func resetDaily() {
        performRolloverIfNeeded()
        snapshot.resetDaily(at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        endLiveActivity()
        if isRunning { presentRunningActivity() }
        #endif
    }

    /// Zero today and forget the cached past totals. The caller deletes the
    /// Sessions; the derived All-Time Total is then zero everywhere.
    func resetTotal() {
        resetDaily()
        setPastTotal(0)
    }

    // MARK: - Manual edit support

    /// A Manual Edit for the current Study Day changes the Clock; edits of
    /// other days only touch Sessions and reach the total via `setPastTotal`.
    func applyManualEdit(date: Date, duration: TimeInterval) {
        performRolloverIfNeeded()
        guard Calendar.current.startOfDay(for: date) == snapshot.studyDay else { return }
        snapshot.setManualDaily(duration, at: Date(), device: deviceID)
        commit()
        #if os(iOS)
        updateLiveActivityInPlace()
        #endif
    }

    // MARK: - Derived totals cache

    /// Set by `StudyStore` whenever Sessions change.
    func setPastTotal(_ total: TimeInterval) {
        pastTotal = total
        suite.set(total, forKey: TimerKey.pastTotal)
        tick += 1
    }

    // MARK: - Private helpers

    /// Write the state everywhere after a Clock Action.
    private func commit() {
        snapshot.write(to: suite)
        syncDisplayTimer()
        persistCurrentDaySession()
        tick += 1
        onStateChanged?(snapshot)
    }

    /// Runs the Rollover; any departing day is queued for persistence.
    @discardableResult
    private func performRolloverIfNeeded() -> Bool {
        let before = snapshot.studyDay
        if let day = snapshot.rollover(now: Date()) {
            ClockSnapshot.enqueue(day, in: suite)
            drainPendingSessions()
        }
        return snapshot.studyDay != before
    }

    private func drainPendingSessions() {
        guard let persistSession else { return }
        let pending = ClockSnapshot.pendingDepartingDays(in: suite)
        guard !pending.isEmpty else { return }
        ClockSnapshot.clearPendingDepartingDays(in: suite)
        for day in pending {
            persistSession(day.date, day.duration)
        }
    }

    private func persistCurrentDaySession() {
        guard snapshot.studyDay > .distantPast else { return }
        let duration = snapshot.daily(at: Date())
        guard duration > 0 else { return }
        persistSession?(snapshot.studyDay, duration)
    }

    private func syncDisplayTimer() {
        stopDisplayTimer()
        if isRunning { startDisplayTimer() }
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
    private func contentForCurrentState() -> ActivityContent<LSATTimerAttributes.ContentState> {
        let staleAt = Date.now.addingTimeInterval(liveActivityIdleTimeout)
        return ActivityContent(state: snapshot.liveActivityState, staleDate: staleAt)
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

    /// Refresh an on-screen card without changing its lifecycle. Only for
    /// changes that leave the clock in the same run state (goal, manual edit);
    /// never for a pause, which must end-with-grace instead.
    private func updateLiveActivityInPlace() {
        let content = contentForCurrentState()
        enqueueActivityOp {
            for activity in Activity<LSATTimerAttributes>.updatable {
                await activity.update(content)
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
        let content = ActivityContent(state: snapshot.endedLiveActivityState, staleDate: nil)
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
            dailyGoal: snapshot.dailyGoal, isEnded: true
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
