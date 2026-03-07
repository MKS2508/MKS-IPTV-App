#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct MKSDownloadActivityBundle: WidgetBundle {
    var body: some Widget {
        MKSDownloadActivityLiveActivity()
    }
}
#endif
