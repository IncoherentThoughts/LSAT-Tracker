import WidgetKit
import SwiftUI
import AppIntents
#if os(iOS)
import ActivityKit
#endif

// Control Center tile: one toggle that starts or pauses the Clock.
// Controls exist on iOS 18+ and — per the SDK — macOS 26+ (Control Center
// widgets arrived on the Mac with Tahoe), hence the availability gates.
//
// `ControlWidgetToggle` needs a `SetValueIntent`, which `ToggleTimerIntent`
// is not (that one is a `LiveActivityIntent` dispatched through the app on
// iOS). `SetClockRunningIntent` below performs the same Clock Action in the
// suite, but only when the requested value differs from the current state —
// a toggle that is already in the requested position is a no-op, matching
// the Clock's own "start when running is a no-op" rule.

// MARK: - Control

@available(iOS 18.0, macOS 26.0, *)
struct LSATTimerControl: ControlWidget {
    static let kind = "LSATTimerControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ClockRunningProvider()) { isRunning in
            ControlWidgetToggle(
                "LSAT Timer",
                isOn: isRunning,
                action: SetClockRunningIntent()
            ) { isOn in
                Label(isOn ? "Running" : "Paused", systemImage: isOn ? "pause.fill" : "book.fill")
                    .controlWidgetActionHint(isOn ? "Pause" : "Start")
            }
            .tint(Color.rosyCopper)
        }
        .displayName("LSAT Timer")
        .description("Start or pause the LSAT study timer.")
    }
}

/// Reads whether the Clock is running straight from the suite.
@available(iOS 18.0, macOS 26.0, *)
struct ClockRunningProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return false }
        return ClockSnapshot(suite: suite).isRunning
    }
}

// MARK: - Intent

/// Sets the Clock to running (`true`) or paused (`false`). Same suite /
/// Rollover / write / notify sequence as `ToggleTimerIntent`, and reuses its
/// `presentLiveActivity`/`notifyApp` helpers (internal, defined in
/// `ToggleTimerIntent.swift`, which this target also compiles).
struct SetClockRunningIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set LSAT Timer Running"
    static let description = IntentDescription("Starts or pauses the LSAT study timer.")
    static let openAppWhenRun = false

    @Parameter(title: "Running")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        guard let suite = UserDefaults(suiteName: appGroupSuite) else { return .result() }
        var snap = ClockSnapshot(suite: suite)
        guard snap.isRunning != value else { return .result() }
        let now = Date()
        if let day = snap.rollover(now: now) {
            ClockSnapshot.enqueue(day, in: suite)
        }
        let device = ClockSnapshot.deviceID(in: suite)
        if value {
            snap.start(at: now, device: device)
        } else {
            snap.pause(at: now, device: device)
        }
        snap.write(to: suite)
        await presentLiveActivity(for: snap, allowRequest: false)
        notifyApp()
        return .result()
    }
}
