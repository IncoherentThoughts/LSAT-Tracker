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
    @State private var timerManager: TimerManager
    @State private var studyStore = StudyStore()

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var navigation = WindowNavigation()
    /// Held for the life of the process; it re-arms itself after each firing.
    @State private var rollover: MacRolloverScheduler
    #endif

    init() {
        let timerManager = TimerManager()
        _timerManager = State(initialValue: timerManager)
        #if os(macOS)
        _rollover = State(initialValue: MacRolloverScheduler(timer: timerManager))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        macScenes
        #else
        WindowGroup {
            MainTabView()
                .environment(timerManager)
                .environment(studyStore)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: StudySession.self) { result in
            if case .success(let container) = result {
                wireStudyStore(to: container)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handle(newPhase)
        }
        #endif
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            timerManager.onForeground()
        case .background, .inactive:
            timerManager.onBackground()
        @unknown default:
            break
        }
    }

    private func wireStudyStore(to container: ModelContainer) {
        studyStore.modelContext = container.mainContext
        studyStore.timer = timerManager
        timerManager.persistSession = { [weak studyStore] date, duration in
            studyStore?.upsertSession(date: date, duration: duration)
        }
        // A merge can leave two records for one day; resolve them before
        // anything derives a total from the history. This also seeds the
        // cached past-Sessions sum the widgets read.
        studyStore.dedupeSessions()
    }
}

// MARK: - macOS scenes

#if os(macOS)
private extension LSAT_TrackerApp {
    /// The Mac app is a menu bar agent: the Menu Bar Item is always there,
    /// and the single main window (same three screens, fixed 420×780) opens
    /// from the popover or the Dock. `Window` rather than `WindowGroup` so
    /// "Open LSAT Tracker" reuses the window when it is already open.
    @SceneBuilder
    var macScenes: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(timerManager)
                .environment(studyStore)
        } label: {
            MenuBarLabel()
                .environment(timerManager)
        }
        .menuBarExtraStyle(.window)

        Window("LSAT Tracker", id: AppDelegate.mainWindowID) {
            MainTabView()
                .frame(width: 420, height: 780)
                .environment(timerManager)
                .environment(studyStore)
                .environment(navigation)
                .preferredColorScheme(.light)
                .onAppear {
                    appDelegate.mainWindowDidOpen()
                    timerManager.onForeground()
                }
                .onDisappear { appDelegate.mainWindowDidClose() }
        }
        .modelContainer(for: StudySession.self) { result in
            if case .success(let container) = result {
                wireStudyStore(to: container)
            }
        }
        .defaultSize(width: 420, height: 780)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, newPhase in
            handle(newPhase)
        }
        .commands {
            // ⌘1 Timer, ⌘2 Stats, ⌘3 Settings. The window follows
            // `navigation`; the capsule tab bar writes back into it.
            CommandMenu("Go") {
                ForEach(Array(WindowNavigation.commandOrder.enumerated()), id: \.element) { index, tab in
                    Button {
                        navigation.select(tab)
                    } label: {
                        if navigation.selectedTab == tab {
                            Label(tab.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(tab.menuTitle)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            // A single-window agent has nothing to make new.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
#endif
