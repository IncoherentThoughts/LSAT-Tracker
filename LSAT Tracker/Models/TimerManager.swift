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
}

let appGroupSuite = "group.evan.lsattimer"

@Observable
final class TimerManager {
    // MARK: - Observed state (drives UI)
    private(set) var dailyElapsed: TimeInterval = 0
    private(set) var totalElapsed: TimeInterval = 0
    private(set) var isRunning: Bool = false
    private(set) var tick: Int = 0

    // MARK: - Private
    private var timerStartedAt: Date?
    private var displayTimer: Timer?
    private let suite: UserDefaults
    #if os(iOS)
    private var liveActivity: Activity<LSATTimerAttributes>?
    #endif

    // MARK: - Init
    init() {
        suite = UserDefaults(suiteName: appGroupSuite) ?? .standard
        rehydrate()
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

    /// Call on every app foreground: check 4am boundary + rehydrate
    func onForeground() {
        check4amBoundary()
        rehydrate()
        stopDisplayTimer()
        if isRunning {
            startDisplayTimer()
        }
        #if os(iOS)
        if liveActivity == nil {
            liveActivity = Activity<LSATTimerAttributes>.activities.first
        }
        updateLiveActivity()
        #endif
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
        startDisplayTimer()
        #if os(iOS)
        startOrUpdateLiveActivity()
        #endif
    }

    func pause() {
        guard isRunning else { return }
        let interval = timerStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        dailyElapsed += interval
        totalElapsed += interval
        timerStartedAt = nil
        isRunning = false
        stopDisplayTimer()
        persistState()
        #if os(iOS)
        updateLiveActivity()
        #endif
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    // MARK: - Resets

    func resetDaily() {
        let wasRunning = isRunning
        if wasRunning { pause() }
        dailyElapsed = 0
        suite.set(0.0, forKey: TimerKey.dailyElapsed)
        #if os(iOS)
        endLiveActivity()
        #endif
        if wasRunning { start() }
    }

    func resetTotal() {
        let wasRunning = isRunning
        if wasRunning { pause() }
        dailyElapsed = 0
        totalElapsed = 0
        suite.set(0.0, forKey: TimerKey.dailyElapsed)
        suite.set(0.0, forKey: TimerKey.totalElapsed)
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

        // Roll daily into total and reset daily
        let savedDaily = suite.double(forKey: TimerKey.dailyElapsed)
        let savedTotal = suite.double(forKey: TimerKey.totalElapsed)
        let newTotal = savedTotal + savedDaily

        suite.set(0.0, forKey: TimerKey.dailyElapsed)
        suite.set(newTotal, forKey: TimerKey.totalElapsed)
        suite.set(now, forKey: TimerKey.lastResetDate)

        dailyElapsed = 0
        totalElapsed = newTotal
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

    private func startOrUpdateLiveActivity() {
        if let existing = liveActivity, existing.activityState == .active {
            updateLiveActivity()
            return
        }
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] Blocked: Live Activities disabled by user or system.")
            return
        }
        let content = ActivityContent(
            state: makeContentState(),
            staleDate: .now.addingTimeInterval(8 * 3600)
        )
        do {
            liveActivity = try Activity<LSATTimerAttributes>.request(
                attributes: LSATTimerAttributes(),
                content: content
            )
            print("[LiveActivity] Started successfully. ID: \(liveActivity?.id ?? "nil")")
            print("[LiveActivity] Activity state: \(String(describing: liveActivity?.activityState))")
            print("[LiveActivity] All active activities count: \(Activity<LSATTimerAttributes>.activities.count)")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    private func updateLiveActivity() {
        // Always re-scan in case the activity reference is stale
        liveActivity = Activity<LSATTimerAttributes>.activities.first(where: { $0.activityState == .active })
        guard let activity = liveActivity else { return }
        let content = ActivityContent(
            state: makeContentState(),
            staleDate: .now.addingTimeInterval(8 * 3600)
        )
        Task { await activity.update(content) }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        let finalState = LSATTimerAttributes.ContentState(
            dailyElapsed: 0, isRunning: false, timerStartedAt: nil, dailyGoal: currentDailyGoal
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: .now),
                dismissalPolicy: .immediate
            )
        }
        liveActivity = nil
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
