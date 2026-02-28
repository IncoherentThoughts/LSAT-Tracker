import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared constants (duplicated from main app — widget is a separate process)

private let widgetSuite = "group.evan.lsattimer"

private enum TimerKey {
    static let dailyElapsed   = "dailyElapsed"
    static let totalElapsed   = "totalElapsed"
    static let timerRunning   = "timerRunning"
    static let timerStartedAt = "timerStartedAt"
}

private func formatTimer(_ interval: TimeInterval) -> String {
    let total   = Int(max(0, interval))
    let hours   = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

// MARK: - AppIntent (play/pause from widget)

struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle LSAT Timer"
    static let description = IntentDescription("Start or pause the LSAT study timer.")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: widgetSuite) ?? .standard
        let isRunning = defaults.bool(forKey: TimerKey.timerRunning)

        if isRunning {
            // Pause: accumulate the live interval into stored elapsed
            let daily = defaults.double(forKey: TimerKey.dailyElapsed)
            let total = defaults.double(forKey: TimerKey.totalElapsed)
            if let startedAt = defaults.object(forKey: TimerKey.timerStartedAt) as? Date {
                let elapsed = max(0, Date().timeIntervalSince(startedAt))
                defaults.set(daily + elapsed, forKey: TimerKey.dailyElapsed)
                defaults.set(total + elapsed, forKey: TimerKey.totalElapsed)
            }
            defaults.set(false, forKey: TimerKey.timerRunning)
            defaults.removeObject(forKey: TimerKey.timerStartedAt)
        } else {
            // Start: record the current timestamp
            defaults.set(true, forKey: TimerKey.timerRunning)
            defaults.set(Date(), forKey: TimerKey.timerStartedAt)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Timeline Entry

struct TimerEntry: TimelineEntry {
    let date: Date
    let dailyElapsed: TimeInterval
    let isRunning: Bool
    let timerStartedAt: Date?
}

// MARK: - Timeline Provider

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, dailyElapsed: 5400, isRunning: true, timerStartedAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 15 minutes to catch edge cases (4am reset, etc.)
        // Live timer display via Text(_:style:) needs no per-second reload
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> TimerEntry {
        let defaults = UserDefaults(suiteName: widgetSuite) ?? .standard
        let daily      = defaults.double(forKey: TimerKey.dailyElapsed)
        let isRunning  = defaults.bool(forKey: TimerKey.timerRunning)
        let startedAt  = defaults.object(forKey: TimerKey.timerStartedAt) as? Date
        return TimerEntry(date: .now, dailyElapsed: daily, isRunning: isRunning, timerStartedAt: startedAt)
    }
}

// MARK: - Widget View

struct LSATWidgetView: View {
    let entry: TimerEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LSAT Daily")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                // Live-counting text when running — no timeline reload needed
                if entry.isRunning, let startedAt = entry.timerStartedAt {
                    // liveZero is the date at which the displayed counter was 0:00:00
                    let liveZero = startedAt.addingTimeInterval(-entry.dailyElapsed)
                    Text(liveZero, style: .timer)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                } else {
                    Text(formatTimer(entry.dailyElapsed))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
            }

            Spacer()

            Button(intent: ToggleTimerIntent()) {
                Image(systemName: entry.isRunning ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Widget Configuration

#if os(iOS)
struct LSATTimerWidget: Widget {
    let kind = "LSATTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerProvider()) { entry in
            LSATWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LSAT Timer")
        .description("Track your daily study time from the lock screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    LSATTimerWidget()
} timeline: {
    TimerEntry(date: .now, dailyElapsed: 5400, isRunning: false, timerStartedAt: nil)
    TimerEntry(date: .now, dailyElapsed: 5400, isRunning: true, timerStartedAt: .now)
}
#endif
