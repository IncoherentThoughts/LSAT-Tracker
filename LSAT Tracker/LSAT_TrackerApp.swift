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

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(timerManager)
                .environment(studyStore)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: StudySession.self) { result in
            if case .success(let container) = result {
                studyStore.modelContext = container.mainContext
                studyStore.timer = timerManager
                timerManager.persistSession = { [weak studyStore] date, duration in
                    studyStore?.upsertSession(date: date, duration: duration)
                }
                // A merge can leave two records for one day; resolve them
                // before anything derives a total from the history. This also
                // seeds the cached past-Sessions sum the widgets read.
                studyStore.dedupeSessions()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                timerManager.onForeground()
            case .background, .inactive:
                timerManager.onBackground()
            @unknown default:
                break
            }
        }
    }
}
