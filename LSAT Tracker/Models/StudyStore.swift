import Foundation
import SwiftData

// MARK: - Backup data types (shared encoding contract for export/import)

/// The backup file's on-disk shape. These names are a *file format*, not
/// suite keys: `totalElapsed` here is the derived All-Time Total written into
/// the export, and the field must keep its name or every backup a user already
/// exported stops decoding.
private struct StatsBackup: Codable {
    let exportDate: Date
    let dailyElapsed: TimeInterval
    let totalElapsed: TimeInterval
    let lastResetDate: Date?
    let sessions: [SessionBackup]
}

private struct SessionBackup: Codable {
    let date: Date
    let duration: TimeInterval
    let isManualEdit: Bool
}

/// Bridges SwiftData StudySession records with business logic for charts and stats.
@Observable
final class StudyStore {
    var modelContext: ModelContext?

    /// The `TimerManager` whose derived totals this store keeps current.
    weak var timer: TimerManager?

    init() {}

    // MARK: - Write operations (require modelContext)

    /// Create or update the StudySession for a given date.
    func upsertSession(date: Date, duration: TimeInterval, isManual: Bool = false) {
        guard let context = modelContext else { return }
        let normalized = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date == normalized }
        )
        if let existing = try? context.fetch(descriptor).first {
            // Skip no-op writes: an unconditional `updatedAt` bump would make
            // every idle re-persist look like a fresh edit to the merge rule.
            if existing.duration == duration, existing.isManualEdit == isManual {
                return
            }
            existing.duration = duration
            existing.isManualEdit = isManual
            existing.updatedAt = Date()
            existing.needsUpload = true
        } else {
            let session = StudySession(date: normalized, duration: duration, isManualEdit: isManual)
            context.insert(session)
        }
        do {
            try context.save()
        } catch {
            print("StudyStore: save failed — \(error)")
        }
        refreshPastTotals()
    }

    func deleteAllSessions() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<StudySession>()
        let all = (try? context.fetch(descriptor)) ?? []
        for session in all {
            context.delete(session)
        }
        do {
            try context.save()
        } catch {
            print("StudyStore: deleteAllSessions failed — \(error)")
        }
        refreshPastTotals()
    }

    /// Single session lookup — used by ManualEditView to pre-fill the duration field.
    func session(for date: Date) -> StudySession? {
        guard let context = modelContext else { return nil }
        let normalized = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date == normalized }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Derived totals

    /// The All-Time Total implied by a set of Sessions. The Sessions are the
    /// history; the total is always a function of them, never a counter kept
    /// alongside them that can drift.
    func allTimeTotal(sessions: [StudySession]) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    /// Recompute the sum of every Session other than the current Study Day's
    /// (which the Clock covers) and hand it to the timer, which caches it in
    /// the suite for the widgets and intents.
    func refreshPastTotals() {
        guard let timer else { return }
        let past = fetchAllSessions().filter { $0.date != timer.studyDay }
        timer.setPastTotal(allTimeTotal(sessions: past))
    }

    // MARK: - Merge hygiene

    /// Keep one Session per date: the most recently updated wins. Sessions
    /// dated on or after the current Study Day are left to the timer, which
    /// re-persists today from the winning Clock State.
    func dedupeSessions() {
        guard let context = modelContext else { return }
        var seen: [Date: StudySession] = [:]
        var removed = false
        for session in fetchAllSessions() {
            if let kept = seen[session.date] {
                let loser = kept.updatedAt >= session.updatedAt ? session : kept
                let winner = loser === kept ? session : kept
                context.delete(loser)
                seen[session.date] = winner
                removed = true
            } else {
                seen[session.date] = session
            }
        }
        if removed {
            try? context.save()
        }
        refreshPastTotals()
    }

    // MARK: - Backup & Restore

    /// Fetches all sessions and encodes them + current timer state into a dated JSON file
    /// in the system temp directory. Returns the file URL for sharing.
    func exportBackupFile(timer: TimerManager) throws -> URL {
        let sessions = fetchAllSessions()

        let backup = StatsBackup(
            exportDate: Date(),
            dailyElapsed: timer.computedDaily,
            totalElapsed: timer.computedTotal,
            lastResetDate: timer.studyDay > .distantPast ? timer.studyDay : nil,
            sessions: sessions.map {
                SessionBackup(date: $0.date, duration: $0.duration, isManualEdit: $0.isManualEdit)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "lsat-stats-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Parses a backup file and returns a human-readable summary for the confirmation alert.
    /// Call this before `applyBackup` so the user sees what they're restoring.
    func importPreview(from url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StatsBackup.self, from: data)
        let dateStr = backup.exportDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        let hours = String(format: "%.1f", backup.totalElapsed / 3600)
        return "Backup from \(dateStr)\n\(backup.sessions.count) sessions · \(hours)h total\n\nThis will permanently overwrite all current stats."
    }

    /// Restores all sessions and timer state from a backup file.
    ///
    /// Pauses the timer, replaces the Sessions, then installs a paused Clock
    /// State carrying the backup's day. The restore is stamped as a Clock
    /// Action so it wins over whatever stale state another device still holds.
    /// The All-Time Total is not restored as a number — it falls straight out
    /// of the restored Sessions plus the restored day.
    func applyBackup(from url: URL, timer: TimerManager) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StatsBackup.self, from: data)

        // Skip the pause's grace-end: it would freeze a PAUSED card showing
        // the pre-restore elapsed time for 30 minutes. onForeground() below
        // sees not-running with a live card and ends it immediately instead.
        if timer.isRunning { timer.pause(endingLiveActivity: false) }

        deleteAllSessions()
        guard let context = modelContext else { return }
        for s in backup.sessions {
            context.insert(StudySession(date: s.date, duration: s.duration, isManualEdit: s.isManualEdit))
        }
        try? context.save()

        var restored = ClockSnapshot()
        restored.studyDay = backup.lastResetDate.map { Calendar.current.startOfDay(for: $0) }
            ?? ClockSnapshot.studyDayStart(for: Date())
        restored.dailyBase = backup.dailyElapsed
        restored.dailyGoal = timer.dailyGoal
        restored.lastActionAt = Date()
        timer.adopt(restored, notify: true)
        refreshPastTotals()

        // The restore left the Clock paused; onForeground() sees not-running
        // with a live card and ends it immediately, so no card is left frozen
        // on the pre-restore elapsed time.
        timer.onForeground()
    }

    // MARK: - Private helpers

    private func fetchAllSessions() -> [StudySession] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\StudySession.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Stats
    // All methods below accept a pre-fetched [StudySession] from @Query in the calling view.
    // This lets SwiftUI's reactive system (not a manual `lastUpdated` flag) drive re-renders.

    func bestDay(from sessions: [StudySession]) -> StudySession? {
        sessions.max(by: { $0.duration < $1.duration })
    }

    func streak(from sessions: [StudySession]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateSet = Set(sessions.filter { $0.duration >= 60 }.map { $0.date })

        var count = 0
        var check = today
        // If today has no study time yet, start from yesterday
        if !dateSet.contains(today) {
            check = calendar.date(byAdding: .day, value: -1, to: today)!
        }
        while dateSet.contains(check) {
            count += 1
            check = calendar.date(byAdding: .day, value: -1, to: check)!
        }
        return count
    }

    func dailyAverage(from sessions: [StudySession], days: Int = 30) -> TimeInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))!
        let recent = sessions.filter { $0.date >= start }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.duration } / Double(days)
    }

    // MARK: - Chart data

    func lastNDays(_ n: Int, from sessions: [StudySession]) -> [(date: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sessionMap = Dictionary(sessions.map { ($0.date, $0.duration) }, uniquingKeysWith: { $1 })
        return (0..<n).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return (date, sessionMap[date] ?? 0)
        }
    }

    func lastNWeeks(_ n: Int, from sessions: [StudySession]) -> [(weekStart: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<n).reversed().map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeekStart)!
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            let total = sessions
                .filter { $0.date >= weekStart && $0.date <= weekEnd }
                .reduce(0) { $0 + $1.duration }
            return (weekStart, total)
        }
    }

    func monthDays(containing date: Date, from sessions: [StudySession]) -> [(date: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let daysInMonth = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        let sessionMap = Dictionary(sessions.map { ($0.date, $0.duration) }, uniquingKeysWith: { $1 })
        return (0..<daysInMonth).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start)!
            return (day, sessionMap[day] ?? 0)
        }
    }
}
