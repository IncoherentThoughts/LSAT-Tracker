import WidgetKit
import SwiftUI

@main
struct LSATWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        LSATTimerLiveActivity()
        #endif
        // #12 adds the macOS Notification Center and Control Center widgets here.
    }
}
