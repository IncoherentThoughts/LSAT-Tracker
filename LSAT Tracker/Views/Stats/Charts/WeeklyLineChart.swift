import SwiftUI
import Charts

struct WeeklyLineChart: View {
    let data: [(weekStart: Date, duration: TimeInterval)]

    var body: some View {
        Chart {
            ForEach(data, id: \.weekStart) { entry in
                AreaMark(
                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                    y: .value("Hours", entry.duration / 3600)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.rosyCopper.opacity(0.25), Color.rosyCopper.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                    y: .value("Hours", entry.duration / 3600)
                )
                .foregroundStyle(Color.rosyCopper)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .symbol(Circle().strokeBorder(lineWidth: 2))
                .symbolSize(40)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
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
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
    let data = (0..<8).reversed().map { offset -> (weekStart: Date, duration: TimeInterval) in
        let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
        return (week, TimeInterval.random(in: 0...72000))
    }
    return WeeklyLineChart(data: data)
        .padding()
        .background(Color.eggshell)
}
