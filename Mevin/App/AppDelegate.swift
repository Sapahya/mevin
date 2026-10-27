import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory keeps Mevin out of the Dock and the app switcher; the menu
        // bar item is the whole interface.
        NSApp.setActivationPolicy(.accessory)
        MevinNotificationService.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        let controller = PanelController(model: model)
        controller.install()
        self.controller = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.recordAbandonedSessionOnQuit()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            model.handleNotificationResponse(response)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
