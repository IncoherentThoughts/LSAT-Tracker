import SwiftUI
import Charts

struct DailyBarChart: View {
    let data: [(date: Date, duration: TimeInterval)]

    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        Chart {
            ForEach(data, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Hours", entry.duration / 3600)
                )
                .foregroundStyle(
                    Calendar.current.startOfDay(for: entry.date) == today
                        ? Color.rosyCopper
                        : Color.lightBronze.opacity(0.6)
                )
                .cornerRadius(4)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .foregroundStyle(Color.lightBronze)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                            .foregroundStyle(Color.lightBronze)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.lightBronze.opacity(0.3))
            }
        }
        .frame(height: 160)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let data = (0..<7).reversed().map { offset -> (date: Date, duration: TimeInterval) in
        let date = calendar.date(byAdding: .day, value: -offset, to: today)!
        return (date, TimeInterval.random(in: 0...14400))
    }
    return DailyBarChart(data: data)
        .padding()
        .background(Color.eggshell)
}
