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
