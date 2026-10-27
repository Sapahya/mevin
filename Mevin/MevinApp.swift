import SwiftUI

@main
struct MevinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The interface lives in a panel owned by PanelController, so this
        // scene exists only because SwiftUI requires one. Settings contributes
        // no window of its own for an accessory app.
        Settings {
            EmptyView()
        }
    }
}
