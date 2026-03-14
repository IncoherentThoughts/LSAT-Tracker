import SwiftUI

struct MonthlyHeatmap: View {
    let data: [(date: Date, duration: TimeInterval)]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    private var maxDuration: TimeInterval {
        data.map(\.duration).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(dayLabels.indices, id: \.self) { index in
                    Text(dayLabels[index])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.lightBronze)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leadingOffset, id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(data, id: \.date) { entry in
                    DayCell(
                        date: entry.date,
                        duration: entry.duration,
                        maxDuration: maxDuration
                    )
                }
            }
        }
    }

    private var leadingOffset: Int {
        guard let first = data.first?.date else { return 0 }
        return Calendar.current.component(.weekday, from: first) - 1
    }
}

private struct DayCell: View {
    let date: Date
    let duration: TimeInterval
    let maxDuration: TimeInterval

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var intensity: Double {
        guard maxDuration > 0, duration > 0 else { return 0 }
        return min(1.0, duration / maxDuration)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    duration > 0
                        ? Color.rosyCopper.opacity(0.15 + 0.7 * intensity)
                        : Color.toffeeBrown.opacity(0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? Color.rosyCopper : .clear, lineWidth: 1.5)
                )

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(
                    intensity > 0.5 ? .toffeeBrown : .lightBronze
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let monthInterval = calendar.dateInterval(of: .month, for: today)!
    let days = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 28
    let data = (0..<days).map { offset -> (date: Date, duration: TimeInterval) in
        let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start)!
        return (date, TimeInterval.random(in: 0...14400))
    }
    return MonthlyHeatmap(data: data)
        .padding()
        .background(Color.eggshell)
}
