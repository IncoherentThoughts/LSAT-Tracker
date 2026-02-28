import SwiftUI

struct TimerDisplay: View {
    let elapsed: TimeInterval
    var fontSize: CGFloat = 72
    var color: Color = .toffeeBrown

    var body: some View {
        Text(elapsed.timerFormatted)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
    }
}

#Preview {
    TimerDisplay(elapsed: 3661)
        .padding()
        .background(Color.eggshell)
}
