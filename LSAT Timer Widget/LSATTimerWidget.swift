import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// MARK: - Toggle Intent

struct ToggleTimerIntent: LiveActivityIntent {
    static let openAppWhenRun = false
    static var title: LocalizedStringResource = "Toggle LSAT Timer"
    static var description = IntentDescription("Starts or pauses the LSAT study timer.")

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: "group.evan.lsattimer")
        let isRunning = suite?.bool(forKey: "timerRunning") ?? false
        let goalRaw = suite?.double(forKey: "dailyGoal") ?? 0
        let dailyGoal = goalRaw > 0 ? goalRaw : 14400

        let newIsRunning: Bool
        let newStartedAt: Date?
        let newDailyElapsed: Double

        if isRunning {
            let stored = suite?.double(forKey: "dailyElapsed") ?? 0
            if let startedAt = suite?.object(forKey: "timerStartedAt") as? Date {
                let interval = max(0, Date().timeIntervalSince(startedAt))
                let daily = stored + interval
                let total = (suite?.double(forKey: "totalElapsed") ?? 0) + interval
                suite?.set(daily, forKey: "dailyElapsed")
                suite?.set(total, forKey: "totalElapsed")
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
            newIsRunning = true
            newStartedAt = startDate
            newDailyElapsed = suite?.double(forKey: "dailyElapsed") ?? 0
        }

        // Push the new state into the Live Activity immediately
        let newState = LSATTimerAttributes.ContentState(
            dailyElapsed: newDailyElapsed,
            isRunning: newIsRunning,
            timerStartedAt: newStartedAt,
            dailyGoal: dailyGoal
        )
        let content = ActivityContent(state: newState, staleDate: .now.addingTimeInterval(8 * 3600))
        for activity in Activity<LSATTimerAttributes>.activities {
            await activity.update(content)
        }
        return .result()
    }
}

// MARK: - Helpers

/// Returns a reference date anchored so that Text(.timer) auto-counts up to the
/// current total elapsed time: `now - referenceDate == dailyElapsed + (now - startedAt)`.
private func liveAnchor(elapsed: TimeInterval, startedAt: Date) -> Date {
    startedAt.addingTimeInterval(-elapsed)
}

/// Formats elapsed seconds as M:SS / MM:SS (under 1 h) or H:MM:SS (1 h+).
/// No leading zero on hours; always two digits for minutes and seconds.
private func fmtElapsed(_ t: TimeInterval) -> String {
    let s = Int(max(0, t))
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%02d:%02d", m, sec)
}

// MARK: - Reusable sub-views

/// App icon view.
/// Fallback: toffeeBrown rounded rect + book glyph.
/// Real icon: add an Image Set named "LSATAppIcon" to the widget extension's
/// Assets.xcassets (Xcode → LSAT Timer Widget target → Assets.xcassets →
/// + → New Image Set → name "LSATAppIcon" → drag your icon PNG in).
/// Once added the real icon covers the fallback automatically.
private struct AppIconView: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            // Fallback layer (always present)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.toffeeBrown)
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color.eggshell)
            // Real icon layer — invisible until "LSATAppIcon" is added to widget assets
            Image("LSATAppIcon")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// Circular progress ring shown in the minimal Dynamic Island slot when another
/// activity is competing. Outer arc = daily goal progress; center = pause/play icon.
private struct ProgressRingView: View {
    var progress: Double
    var isRunning: Bool
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.toffeeBrown.opacity(0.35), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.rosyCopper,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Lock Screen View

struct LSATLockScreenView: View {
    let context: ActivityViewContext<LSATTimerAttributes>

    private var progress: Double {
        guard context.state.dailyGoal > 0 else { return 0 }
        return min(1.0, context.state.dailyElapsed / context.state.dailyGoal)
    }

    /// Live-counting timer when running; static formatted string when paused.
    @ViewBuilder
    private var timerDisplay: some View {
        if context.state.isRunning, let startedAt = context.state.timerStartedAt {
            Text(
                liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt),
                style: .timer
            )
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.primary)
        } else {
            Text(fmtElapsed(context.state.dailyElapsed))
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: icon + title + toggle button
            HStack(spacing: 10) {
                AppIconView(size: 42)
                Text("Study Timer")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(intent: ToggleTimerIntent()) {
                    Image(
                        systemName: context.state.isRunning
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.system(size: 44))
                    .foregroundStyle(Color.eggshell)
                    .symbolRenderingMode(.hierarchical)
                }
            }

            // Large timer
            timerDisplay

            // Daily goal progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.25))
                        .frame(height: 14)
                    Capsule()
                        .fill(Color.rosyCopper)
                        .frame(width: geo.size.width * progress, height: 14)
                }
            }
            .frame(height: 14)
        }
        .padding()
        .activityBackgroundTint(Color.toffeeBrown)
    }
}

// MARK: - Live Activity Widget

struct LSATTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LSATTimerAttributes.self) { context in
            LSATLockScreenView(context: context)
        } dynamicIsland: { context in
            let progress = context.state.dailyGoal > 0
                ? min(1.0, context.state.dailyElapsed / context.state.dailyGoal)
                : 0.0

            return DynamicIsland {
                // ── Expanded (long-press) ──────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    AppIconView(size: 38)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isRunning, let startedAt = context.state.timerStartedAt {
                        Text(
                            liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt),
                            style: .timer
                        )
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    } else {
                        Text(fmtElapsed(context.state.dailyElapsed))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: ToggleTimerIntent()) {
                        Image(
                            systemName: context.state.isRunning
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.rosyCopper)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }

            // ── Compact (this is the only Live Activity) ───────────────────
            } compactLeading: {
                AppIconView(size: 16)
            } compactTrailing: {
                if context.state.isRunning, let startedAt = context.state.timerStartedAt {
                    Text(
                        liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt),
                        style: .timer
                    )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                } else {
                    Text(fmtElapsed(context.state.dailyElapsed))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }

            // ── Minimal (competing Live Activity is also showing) ──────────
            } minimal: {
                ProgressRingView(progress: progress, isRunning: context.state.isRunning, size: 26)
            }
        }
    }
}
