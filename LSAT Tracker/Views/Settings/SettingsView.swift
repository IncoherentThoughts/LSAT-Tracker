import SwiftUI

struct SettingsView: View {
    @Environment(TimerManager.self) private var timer
    @Environment(StudyStore.self) private var store

    @State private var showResetDailyAlert = false
    @State private var showResetTotalAlert1 = false
    @State private var showResetTotalAlert2 = false
    @State private var showManualEdit = false
    @State private var dailyGoalHours: Int = 4

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Timer Controls
                Section("Timer") {
                    HStack {
                        Label("Daily Goal", systemImage: "target")
                            .foregroundColor(.toffeeBrown)
                        Spacer()
                        Stepper("\(dailyGoalHours)h", value: $dailyGoalHours, in: 1...10)
                            .onChange(of: dailyGoalHours) { _, newValue in
                                UserDefaults(suiteName: appGroupSuite)?.set(
                                    Double(newValue) * 3600, forKey: "dailyGoal"
                                )
                            }
                            .foregroundColor(.lightBronze)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))

                    Button(role: .destructive) {
                        showResetDailyAlert = true
                    } label: {
                        Label("Reset Daily Timer", systemImage: "arrow.counterclockwise.circle")
                            .foregroundColor(.toffeeBrown)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))

                    Button(role: .destructive) {
                        showResetTotalAlert1 = true
                    } label: {
                        Label("Reset Total Timer", systemImage: "trash.circle")
                            .foregroundColor(.toffeeBrown)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))
                }

                // MARK: Advanced
                Section {
                    DisclosureGroup("Advanced") {
                        Button {
                            showManualEdit = true
                        } label: {
                            Label("Manual Day Edit", systemImage: "pencil.and.list.clipboard")
                                .foregroundColor(.toffeeBrown)
                        }
                    }
                }
                .listRowBackground(Color.toffeeBrown.opacity(0.08))

                // MARK: About
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundColor(.toffeeBrown)
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.lightBronze)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.eggshell)
            .onAppear {
                let g = UserDefaults(suiteName: appGroupSuite)?.double(forKey: "dailyGoal") ?? 0
                dailyGoalHours = g > 0 ? Int(g / 3600) : 4
            }
            .navigationTitle("Settings")
            .tint(.rosyCopper)
        }
        .alert("Reset Daily Timer?", isPresented: $showResetDailyAlert) {
            Button("Reset", role: .destructive) {
                timer.resetDaily()
                store.upsertSession(date: Date(), duration: 0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today's study time will be reset to 0:00:00.")
        }
        .alert("Reset All-Time Total?", isPresented: $showResetTotalAlert1) {
            Button("Continue", role: .destructive) {
                showResetTotalAlert2 = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently erase your all-time study total. Are you sure?")
        }
        .alert("This Cannot Be Undone", isPresented: $showResetTotalAlert2) {
            Button("Reset Everything", role: .destructive) {
                timer.resetTotal()
                store.deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your entire study history total will be permanently deleted.")
        }
        .sheet(isPresented: $showManualEdit) {
            ManualEditView()
                .environment(timer)
                .environment(store)
        }
    }
}

#Preview {
    SettingsView()
        .environment(TimerManager())
        .environment(StudyStore())
}
