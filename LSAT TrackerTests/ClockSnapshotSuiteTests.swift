import Foundation
import Testing
@testable import LSAT_Tracker

/// Round-trips through an isolated UserDefaults suite, including the
/// migration from the pre-sync key layout.
struct ClockSnapshotSuiteTests {
    func freshSuite() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func roundTripsThroughTheSuite() {
        let suite = freshSuite()
        var s = ClockSnapshot()
        s.studyDay = Calendar.current.startOfDay(for: Date())
        s.dailyBase = 42
        s.dailyGoal = 7200
        s.start(at: Date(), device: "dev")
        s.write(to: suite)
        #expect(ClockSnapshot(suite: suite) == s)
    }

    /// The migration that protects real device history: an install that has
    /// only ever written `lastResetDate` must carry its Study Day and its
    /// banked seconds across unchanged, with no day lost to `.distantPast`
    /// and no spurious rollover crediting today's minutes to 1 January 1.
    @Test func migratesLegacyLastResetDateIntoStudyDay() {
        let suite = freshSuite()
        let legacy = Date().addingTimeInterval(-86400 * 3)
        suite.set(legacy, forKey: TimerKey.legacyLastResetDate)
        suite.set(120.0, forKey: TimerKey.dailyElapsed)
        let s = ClockSnapshot(suite: suite)
        #expect(s.studyDay == Calendar.current.startOfDay(for: legacy))
        #expect(s.dailyBase == 120)
    }

    /// `studyDay` is authoritative once written, so a second launch does not
    /// fall back to the legacy key and re-derive a day that has moved on.
    @Test func studyDayWinsOverTheLegacyKeyOnceWritten() {
        let suite = freshSuite()
        let legacy = Date().addingTimeInterval(-86400 * 3)
        suite.set(legacy, forKey: TimerKey.legacyLastResetDate)
        var migrated = ClockSnapshot(suite: suite)
        _ = migrated.rollover(now: Date())
        migrated.write(to: suite)

        let reloaded = ClockSnapshot(suite: suite)
        #expect(reloaded.studyDay == migrated.studyDay)
        #expect(reloaded.studyDay != Calendar.current.startOfDay(for: legacy))
    }

    /// The departing day a legacy install leaves behind is banked exactly
    /// once: its seconds become a Session and the new day starts at zero.
    @Test func legacyInstallBanksItsDepartingDayExactlyOnce() {
        let suite = freshSuite()
        let legacy = Date().addingTimeInterval(-86400 * 3)
        suite.set(legacy, forKey: TimerKey.legacyLastResetDate)
        suite.set(3600.0, forKey: TimerKey.dailyElapsed)

        var s = ClockSnapshot(suite: suite)
        let departing = s.rollover(now: Date())
        #expect(departing?.duration == 3600)
        #expect(departing?.date == Calendar.current.startOfDay(for: legacy))
        #expect(s.dailyBase == 0)
        // Running it again banks nothing further.
        #expect(s.rollover(now: Date()) == nil)
    }

    @Test func queuesAndDrainsDepartingDays() {
        let suite = freshSuite()
        let day = DepartingDay(date: Date(), duration: 10)
        ClockSnapshot.enqueue(day, in: suite)
        ClockSnapshot.enqueue(day, in: suite)
        #expect(ClockSnapshot.pendingDepartingDays(in: suite).count == 2)
        ClockSnapshot.clearPendingDepartingDays(in: suite)
        #expect(ClockSnapshot.pendingDepartingDays(in: suite).isEmpty)
    }
}
