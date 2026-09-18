import SwiftUI
import AppIntents

// `ToggleTimerIntent` lives in `LSAT Tracker/Models/ToggleTimerIntent.swift`
// so both the main app and the widget extension target compile the same type.
// `Button(intent:)` in the Live Activity view depends on the main app being
// able to resolve the intent class — otherwise iOS silently drops the tap.
//
// These pieces are shared by the Live Activity (iOS), the Notification
// Center widget (iOS), and the Mac menu bar popover (macOS). Nothing here
// may depend on WidgetKit or ActivityKit — those stay in the iOS-only
// consumers so this file compiles for the main app target on macOS too.

// MARK: - Helpers

/// Returns a reference date anchored so that Text(.timer) auto-counts up to the
/// current total elapsed time: `now - referenceDate == dailyElapsed + (now - startedAt)`.
func liveAnchor(elapsed: TimeInterval, startedAt: Date) -> Date {
    startedAt.addingTimeInterval(-elapsed)
}

/// Formats elapsed seconds as M:SS / MM:SS (under 1 h) or H:MM:SS (1 h+).
/// No leading zero on hours; always two digits for minutes and seconds.
func fmtElapsed(_ t: TimeInterval) -> String {
    let s = Int(max(0, t))
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%02d:%02d", m, sec)
}

// MARK: - AppIconView

/// App icon view.
/// Fallback: toffeeBrown rounded rect + book glyph.
/// Real icon: add an Image Set named "LSATAppIcon" to the widget extension's
/// Assets.xcassets (Xcode → LSAT Timer Widget target → Assets.xcassets →
/// + → New Image Set → name "LSATAppIcon" → drag your icon PNG in).
/// Once added the real icon covers the fallback automatically.
struct AppIconView: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.toffeeBrown)
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color.eggshell)
            Image("LSATAppIcon")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Widget Play/Pause Button

struct WidgetPlayPauseButton: View {
    let isRunning: Bool

    var body: some View {
        // Pass the desired end state explicitly: if this button was rendered
        // from a stale snapshot, the intent no-ops instead of inverting the
        // toggle (a "pause" tap can never start the timer).
        Button(intent: ToggleTimerIntent(setRunning: !isRunning)) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.eggshell.opacity(0.9) : Color.rosyCopper)
                    .shadow(
                        color: isRunning
                            ? Color.toffeeBrown.opacity(0.18)
                            : Color.rosyCopper.opacity(0.55),
                        radius: isRunning ? 3 : 7,
                        x: 0,
                        y: isRunning ? 2 : 6
                    )
                if isRunning {
                    Circle()
                        .strokeBorder(Color.toffeeBrown.opacity(0.25), lineWidth: 1)
                }
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isRunning ? Color.toffeeInk : Color(hex: "#FDF6E3"))
                    .offset(x: isRunning ? 0 : 1.5)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timer Digits

/// HH:MM:SS with colons rendered in lightBronze at ultraLight weight.
struct TimerDigitsView: View {
    let elapsed: TimeInterval

    private var h: Int { Int(max(0, elapsed)) / 3600 }
    private var m: Int { (Int(max(0, elapsed)) % 3600) / 60 }
    private var s: Int { Int(max(0, elapsed)) % 60 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            digit(String(h))
            colon
            digit(String(format: "%02d", m))
            colon
            digit(String(format: "%02d", s))
        }
    }

    private func digit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.toffeeInk)
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(Color.lightBronze)
            .baselineOffset(4)
            .padding(.horizontal, 2)
    }
}

// MARK: - Goal Progress Bar

struct GoalProgressBar: View {
    let isRunning: Bool
    let dailyElapsed: TimeInterval
    let dailyGoal: TimeInterval
    let timerStartedAt: Date?
    let goalHours: Int

    private var axisLabels: [String] {
        (0...4).map { i in
            let num = goalHours * i
            if num % 4 == 0 {
                return "\(num / 4)h"
            }
            return String(format: "%.1fh", Double(num) / 4.0)
        }
    }

    private var staticProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1.0, dailyElapsed / dailyGoal)
    }

    /// 25/50/75% divider marks drawn on top of the native bar. They're static
    /// decoration, so overlaying them doesn't interfere with the system ticking
    /// the fill underneath second-by-second on the Lock Screen.
    private var tickMarks: some View {
        GeometryReader { geo in
            ForEach([0.25, 0.5, 0.75] as [Double], id: \.self) { frac in
                Rectangle()
                    .fill(Color.toffeeBrown.opacity(0.35))
                    .frame(width: 1, height: 8)
                    .position(x: geo.size.width * frac, y: geo.size.height / 2)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Use the built-in `.linear` style (NOT a custom ProgressViewStyle):
            // only the system's own rendering of `ProgressView(timerInterval:)`
            // keeps ticking on the Lock Screen without app wakeups. A custom
            // style snapshots `fractionCompleted` once at push time and freezes
            // the bar while running — that was the bug.
            Group {
                if isRunning, let startedAt = timerStartedAt, dailyGoal > 0 {
                    // Anchor chosen so that at `now` the fraction equals
                    // dailyElapsed/dailyGoal, then it ticks forward to 100%
                    // at anchor + dailyGoal — the system updates the
                    // fraction on the Lock Screen with no app wakeups.
                    let anchor = startedAt.addingTimeInterval(-dailyElapsed)
                    let endDate = anchor.addingTimeInterval(dailyGoal)
                    ProgressView(
                        timerInterval: anchor...endDate,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                } else {
                    ProgressView(value: staticProgress)
                }
            }
            .progressViewStyle(.linear)
            .tint(Color.rosyCopper)
            .frame(height: 8)
            .overlay(tickMarks)

            HStack {
                ForEach(Array(axisLabels.enumerated()), id: \.offset) { i, label in
                    if i > 0 { Spacer() }
                    Text(label)
                }
            }
            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
            .tracking(0.76)
            .foregroundStyle(Color.bronzeMuted)
        }
    }
}
