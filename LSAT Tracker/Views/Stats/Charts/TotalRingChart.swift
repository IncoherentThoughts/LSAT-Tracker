import SwiftUI
import Charts

struct TotalRingChart: View {
    let totalSeconds: TimeInterval

    private var totalHours: Double { totalSeconds / 3600 }

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let hours: Double
        let color: Color
    }

    private var buckets: [Bucket] {
        let tiers: [(String, Double, Color)] = [
            ("0–50h",    min(totalHours, 50),                           .lightBronze),
            ("50–100h",  max(0, min(totalHours - 50,  50)),            .rosyCopper),
            ("100–200h", max(0, min(totalHours - 100, 100)),           .skyReflection),
            ("200h+",    max(0, totalHours - 200),                      .toffeeBrown),
        ]
        return tiers.filter { $0.1 > 0 }.map { Bucket(label: $0.0, hours: $0.1, color: $0.2) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Chart(buckets) { bucket in
                SectorMark(
                    angle: .value("Hours", bucket.hours),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(bucket.color)
                .cornerRadius(4)
            }
            .frame(width: 140, height: 140)
            .overlay {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", totalHours))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.toffeeBrown)
                    Text("hours")
                        .font(.caption)
                        .foregroundColor(.lightBronze)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    ("0–50h",    Color.lightBronze),
                    ("50–100h",  Color.rosyCopper),
                    ("100–200h", Color.skyReflection),
                    ("200h+",    Color.toffeeBrown),
                ] as [(String, Color)], id: \.0) { label, color in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                        Text(label)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.toffeeBrown.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    TotalRingChart(totalSeconds: 324000)
        .padding()
        .background(Color.eggshell)
}
