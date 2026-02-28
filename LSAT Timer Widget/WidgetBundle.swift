import WidgetKit
import SwiftUI

#if os(iOS)
@main
struct LSATWidgetBundle: WidgetBundle {
    var body: some Widget {
        LSATTimerWidget()
    }
}
#endif
