//
//  LSAT_TrackerApp.swift
//  LSAT Tracker
//
//  Created by Evan Williams on 2/27/26.
//

import SwiftUI
import SwiftData

@main
struct LSAT_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var timerManager = TimerManager()
    @State private var studyStore = StudyStore()
    @State private var syncClient = SyncClient(
        suite: UserDefaults(suiteName: appGroupSuite) ?? .standard
    )

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(timerManager)
                .environment(studyStore)
                .environment(syncClient)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: StudySession.self) { result in
            if case .success(let container) = result {
                studyStore.modelContext = container.mainContext
                studyStore.timer = timerManager
                studyStore.sync = syncClient
                syncClient.timer = timerManager
                syncClient.store = studyStore
                timerManager.persistSession = { [weak studyStore] date, duration in
                    studyStore?.upsertSession(date: date, duration: duration)
                }
                // Every Clock Action marks the Clock dirty and schedules a
                // flush; the upload itself is the sync client's business.
                timerManager.onStateChanged = { [weak syncClient] _ in
                    syncClient?.clockChanged()
                }
                // A merge can leave two records for one day; resolve them
                // before anything derives a total from the history. This also
                // seeds the cached past-Sessions sum the widgets read.
                studyStore.dedupeSessions()
                // Follow the stored Account session, if this device has one;
                // the SDK keeps the refresh token in the Keychain.
                syncClient.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                timerManager.onForeground()
                syncClient.resume()
            case .background, .inactive:
                timerManager.onBackground()
                syncClient.suspend()
            @unknown default:
                break
            }
        }
    }
}
