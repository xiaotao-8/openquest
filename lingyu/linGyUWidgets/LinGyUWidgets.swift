import SwiftUI
import WidgetKit

/// The widget extension: three widgets plus the two Live Activities.
/// The extension never talks to the host and never sees pairing keys;
/// the widgets read the App Group snapshot the app writes, and the
/// Live Activities are driven from the app by `LiveActivityManager`.
@main
struct LinGyUWidgets: WidgetBundle {
    var body: some Widget {
        RosterWidget()
        NewConversationWidget()
        MiniAppsWidget()
        LinGyUCallActivity()
        LinGyUApprovalActivity()
    }
}
