#if os(iOS)
import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// `ToggleTimerIntent` lives in `LSAT Tracker/Models/ToggleTimerIntent.swift`
// so both the main app and the widget extension target compile the same type.
// `Button(intent:)` in the Live Activity view depends on the main app being
// able to resolve the intent class — otherwise iOS silently drops the tap.
//
// `liveAnchor`, `fmtElapsed`, `AppIconView`, `WidgetPlayPauseButton`,
// `TimerDigitsView` and `GoalProgressBar` live in
// `Views/Shared/SharedWidgetViews.swift` so the Mac menu bar popover can
// reuse them too.

// MARK: - Lock Screen View

struct LSATLockScreenView: View {
    let context: ActivityViewContext<LSATTimerAttributes>

    private var progress: Double {
        guard context.state.dailyGoal > 0 else { return 0 }
        return min(1.0, context.state.dailyElapsed / context.state.dailyGoal)
    }

    private var goalHours: Int {
        max(1, Int(context.state.dailyGoal / 3600))
    }

    private var percentageText: String {
        String(format: "%.0f%%", progress * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ────────────────────────────────────────────────
            HStack(spacing: 10) {
                AppIconView(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("LSAT Tracker")
                        .eyebrowStyle()
                    Text("Study Session")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.13)
                        .foregroundStyle(Color.toffeeInk)
                }

                Spacer()

                // An ended card (paused, riding out its dismissal grace) is a
                // frozen snapshot — a Button(intent:) on it can't re-render,
                // so it would just look broken. Show a quiet static label
                // instead; tapping the card still opens the app to resume.
                if context.state.isEnded == true {
                    Text("PAUSED")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.33)
                        .foregroundStyle(Color.bronzeMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.bronzeMuted.opacity(0.45), lineWidth: 1)
                        )
                        // Match the 44pt play/pause button footprint so the
                        // card height doesn't jump at the pause crossfade.
                        .frame(height: 44)
                        .offset(y: 4)
                } else {
                    WidgetPlayPauseButton(isRunning: context.state.isRunning)
                        .offset(y: 4)
                }
            }

            Spacer().frame(height: 10)

            // ── Timer row ─────────────────────────────────────────────────
            // Use Text(timerInterval:pauseTime:countsDown:) for BOTH states so
            // the view identity stays stable across activity updates. iOS
            // re-renders the whole widget on every state push and crossfades
            // between snapshots; identical view types make the crossfade
            // invisible. pauseTime=nil → ticks natively second-by-second on
            // the Lock Screen with no app wakeups; pauseTime=non-nil → frozen.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let anchor: Date = {
                    if context.state.isRunning, let startedAt = context.state.timerStartedAt {
                        return liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt)
                    }
                    return Date.now.addingTimeInterval(-context.state.dailyElapsed)
                }()
                let pause: Date? = context.state.isRunning ? nil : .now

                Text(
                    timerInterval: anchor...Date.distantFuture,
                    pauseTime: pause,
                    countsDown: false,
                    showsHours: true
                )
                .font(.system(size: 40, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.toffeeInk)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("OF \(goalHours)H GOAL")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.33)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.bronzeMuted)
                    // The bar ticks live while running, but a percentage Text
                    // can't auto-tick (no native API) — it would sit frozen and
                    // stale beside the moving bar. Show it only when paused, when
                    // its value is current.
                    if !context.state.isRunning {
                        Text(percentageText)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .tracking(0.26)
                            .foregroundStyle(Color.toffeeBrown)
                    }
                }
            }

            Spacer().frame(height: 8)

            // ── Progress bar ──────────────────────────────────────────────
            GoalProgressBar(
                isRunning: context.state.isRunning,
                dailyElapsed: context.state.dailyElapsed,
                dailyGoal: context.state.dailyGoal,
                timerStartedAt: context.state.timerStartedAt,
                goalHours: goalHours
            )
        }
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 20))
        .overlay(
            ContainerRelativeShape()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
        .activityBackgroundTint(Color.eggshellDeep.opacity(0.78))
    }
}

// MARK: - Live Activity Widget

struct LSATTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LSATTimerAttributes.self) { context in
            LSATLockScreenView(context: context)
        } dynamicIsland: { context in
            let goalHours = max(1, Int(context.state.dailyGoal / 3600))

            return DynamicIsland {
                // ── Expanded (long-press) ──────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    AppIconView(size: 38)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Group {
                        if context.state.isRunning, let startedAt = context.state.timerStartedAt {
                            Text(
                                liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt),
                                style: .timer
                            )
                        } else {
                            Text(fmtElapsed(context.state.dailyElapsed))
                        }
                    }
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.copperSoft)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: ToggleTimerIntent(setRunning: !context.state.isRunning)) {
                        Image(
                            systemName: context.state.isRunning
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(Color.rosyCopper)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GoalProgressBar(
                        isRunning: context.state.isRunning,
                        dailyElapsed: context.state.dailyElapsed,
                        dailyGoal: context.state.dailyGoal,
                        timerStartedAt: context.state.timerStartedAt,
                        goalHours: goalHours
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }

            // ── Compact (this is the only Live Activity) ───────────────────
            } compactLeading: {
                AppIconView(size: 16)
            } compactTrailing: {
                HStack(spacing: 4) {
                    Group {
                        if context.state.isRunning, let startedAt = context.state.timerStartedAt {
                            Text(
                                liveAnchor(elapsed: context.state.dailyElapsed, startedAt: startedAt),
                                style: .timer
                            )
                        } else {
                            Text(fmtElapsed(context.state.dailyElapsed))
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.copperSoft)

                    if context.state.isRunning {
                        Circle()
                            .fill(Color.rosyCopper)
                            .frame(width: 5, height: 5)
                            .shadow(color: Color.rosyCopper.opacity(0.6), radius: 3, x: 0, y: 0)
                    }
                }

            // ── Minimal (competing Live Activity is also showing) ──────────
            } minimal: {
                Circle()
                    .fill(Color.rosyCopper)
                    .frame(width: 5, height: 5)
                    .shadow(color: Color.rosyCopper.opacity(0.6), radius: 3, x: 0, y: 0)
            }
        }
    }
}
#endif
