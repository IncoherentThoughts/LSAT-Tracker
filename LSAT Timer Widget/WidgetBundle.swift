import WidgetKit
import SwiftUI

@main
struct LSATWidgetBundle: WidgetBundle {
    var body: some Widget {
        LSATTimerWidget()
        #if os(iOS)
        LSATTimerLiveActivity()
        #endif
        if #available(iOS 18.0, macOS 26.0, *) {
            LSATTimerControl()
        }
    }
}
