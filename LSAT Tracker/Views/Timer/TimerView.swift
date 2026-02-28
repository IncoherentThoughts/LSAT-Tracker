import SwiftUI

struct TimerView: View {
    @Environment(TimerManager.self) private var timer
    @State private var buttonScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Daily timer (large, primary)
            TimerDisplay(elapsed: timer.computedDaily)
                .padding(.bottom, 8)

            // Total timer (secondary)
            Text(timer.computedTotal.timerFormatted)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.lightBronze)
                .padding(.bottom, 48)

            // Play/Pause button with pulse ring
            ZStack {
                // Pulse ring (only while running)
                Circle()
                    .stroke(Color.rosyCopper, lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(timer.isRunning ? 1.4 : 1.0)
                    .opacity(timer.isRunning ? pulseOpacity : 0)
                    .animation(
                        timer.isRunning
                            ? .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                            : .default,
                        value: timer.isRunning
                    )

                // Main button
                Button {
                    Task {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            buttonScale = 0.92
                        }
                        try? await Task.sleep(for: .seconds(0.15))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            buttonScale = 1.0
                        }
                    }
                    timer.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.rosyCopper)
                            .frame(width: 72, height: 72)
                            .shadow(color: .rosyCopper.opacity(0.35), radius: 12)

                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.eggshell)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(buttonScale)
                .sensoryFeedback(.impact(weight: .medium), trigger: timer.isRunning)
            }
            .frame(width: 120, height: 120)
            .onAppear { startPulse() }
            .onChange(of: timer.isRunning) { _, running in
                if running { startPulse() }
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.eggshell)
    }

    private func startPulse() {
        pulseOpacity = 0.6
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulseOpacity = 0
        }
    }
}

#Preview {
    TimerView()
        .environment(TimerManager())
}
