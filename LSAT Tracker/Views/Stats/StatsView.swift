import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(StudyStore.self) private var store
    @Environment(TimerManager.self) private var timer
    @Query(sort: \StudySession.date) private var allSessions: [StudySession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: Streak + Summary Cards
                    HStack(spacing: 12) {
                        StreakCard(streak: store.streak(from: allSessions))
                        StatCard(
                            title: "Daily Avg",
                            value: store.dailyAverage(from: allSessions).compactFormatted,
                            icon: "chart.line.uptrend.xyaxis"
                        )
                    }

                    // MARK: Best Day Card
                    if let best = store.bestDay(from: allSessions), best.duration > 0 {
                        BestDayCard(session: best)
                    }

                    // MARK: Daily Bar Chart
                    ChartCard(title: "Last 7 Days") {
                        DailyBarChart(data: todayOverridden(store.lastNDays(7, from: allSessions)))
                    }

                    // MARK: Weekly Line Chart
                    ChartCard(title: "Last 8 Weeks") {
                        WeeklyLineChart(data: store.lastNWeeks(8, from: allSessions))
                    }

                    // MARK: Monthly Heatmap
                    ChartCard(title: "This Month") {
                        MonthlyHeatmap(data: todayOverridden(store.currentMonthDays(from: allSessions)))
                    }

                    // MARK: Total Ring
                    ChartCard(title: "All-Time Hours") {
                        TotalRingChart(totalSeconds: timer.computedTotal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .navigationTitle("Statistics")
            .background(Color.eggshell)
        }
        .onAppear {
            store.upsertSession(date: Date(), duration: timer.computedDaily)
        }
    }

    private func todayOverridden(
        _ days: [(date: Date, duration: TimeInterval)]
    ) -> [(date: Date, duration: TimeInterval)] {
        let today = Calendar.current.startOfDay(for: Date())
        return days.map { entry in
            entry.date == today ? (entry.date, max(entry.duration, timer.computedDaily)) : entry
        }
    }
}

// MARK: - Streak Card

private struct StreakCard: View {
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Streak", systemImage: "flame.fill")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundColor(streak >= 7 ? .skyReflection : .lightBronze)

            Text("\(streak)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(streak >= 7 ? .skyReflection : .toffeeBrown)

            Text("days")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.lightBronze)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.toffeeBrown.opacity(0.08))
        .cornerRadius(16)
        .shadow(color: .toffeeBrown.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundColor(.lightBronze)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.toffeeBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.toffeeBrown.opacity(0.08))
        .cornerRadius(16)
        .shadow(color: .toffeeBrown.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - Best Day Card

private struct BestDayCard: View {
    let session: StudySession

    private var dateString: String {
        session.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Best Day", systemImage: "trophy.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(.skyReflection)
                Text(session.formattedDuration)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.toffeeBrown)
            }
            Spacer()
            Text(dateString)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.lightBronze)
        }
        .padding(16)
        .background(Color.toffeeBrown.opacity(0.08))
        .cornerRadius(16)
        .shadow(color: .toffeeBrown.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - Chart Card Container

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.toffeeBrown)
            content()
        }
        .padding(16)
        .background(Color.toffeeBrown.opacity(0.08))
        .cornerRadius(16)
        .shadow(color: .toffeeBrown.opacity(0.08), radius: 8, y: 2)
    }
}

#Preview {
    StatsView()
        .environment(StudyStore())
        .environment(TimerManager())
}
