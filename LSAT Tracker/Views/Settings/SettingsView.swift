import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(TimerManager.self) private var timer
    @Environment(StudyStore.self) private var store

    @State private var showResetDailyAlert = false
    @State private var showResetTotalAlert1 = false
    @State private var showResetTotalAlert2 = false
    @State private var showManualEdit = false
    @State private var dailyGoalHours: Int = 4

    // Backup & Restore
    @State private var exportFile: ExportFile?
    @State private var showExportError = false
    @State private var exportError = ""
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var importPreviewText = ""
    @State private var showImportConfirm = false
    @State private var showImportError = false
    @State private var importError = ""

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

                // MARK: Backup & Restore
                Section("Backup & Restore") {
                    Button {
                        do {
                            let url = try store.exportBackupFile(timer: timer)
                            exportFile = ExportFile(url: url)
                        } catch {
                            exportError = error.localizedDescription
                            showExportError = true
                        }
                    } label: {
                        Label("Export Stats", systemImage: "square.and.arrow.up")
                            .foregroundColor(.toffeeBrown)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Stats", systemImage: "square.and.arrow.down")
                            .foregroundColor(.toffeeBrown)
                    }
                    .listRowBackground(Color.toffeeBrown.opacity(0.08))
                }

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
        // Export: native share sheet so user can save to Files, AirDrop, etc.
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        // Import: system document picker filtered to JSON files
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    importPreviewText = try store.importPreview(from: url)
                    pendingImportURL = url
                    showImportConfirm = true
                } catch {
                    importError = "Could not read backup: \(error.localizedDescription)"
                    showImportError = true
                }
            case .failure(let error):
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Restore Backup?", isPresented: $showImportConfirm) {
            Button("Restore", role: .destructive) {
                guard let url = pendingImportURL else { return }
                pendingImportURL = nil
                do {
                    try store.applyBackup(from: url, timer: timer)
                } catch {
                    importError = "Import failed: \(error.localizedDescription)"
                    showImportError = true
                }
            }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text(importPreviewText)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError)
        }
    }
}

// MARK: - Helpers

/// Identifiable wrapper so .sheet(item:) can present the share sheet for a URL.
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin UIKit bridge — presents UIActivityViewController for file sharing.
#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    SettingsView()
        .environment(TimerManager())
        .environment(StudyStore())
}
