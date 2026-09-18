import Foundation
import SwiftData
import Testing
@testable import LSAT_Tracker

/// `AppServices` builds the container, the store, the sync client and the
/// timer once, in the App's own `init()` — before any scene, including the
/// Mac `Window`, ever appears (#24). Instantiating it directly here exercises
/// exactly that "no window has ever opened" situation: nothing in this file
/// creates a `WindowGroup`, a `MenuBarExtra`, or a `Window`.
@MainActor
struct AppServicesTests {
    @Test func persistSessionIsWiredWithoutAnyWindowOpening() {
        let services = AppServices()
        #expect(services.timer.persistSession != nil)
    }

    @Test func syncHasStartedWithoutAnyWindowOpening() {
        let services = AppServices()
        #expect(services.sync.hasStarted)
    }

    @Test func storeAndSyncAreWiredToEachOtherAndTheTimer() {
        let services = AppServices()
        #expect(services.store.timer === services.timer)
        #expect(services.store.sync === services.sync)
        #expect(services.sync.timer === services.timer)
        #expect(services.sync.store === services.store)
    }

    @Test func storeSharesTheServicesContainer() {
        let services = AppServices()
        #expect(services.store.modelContext === services.container.mainContext)
    }
}
