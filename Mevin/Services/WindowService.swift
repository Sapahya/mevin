import AppKit
import Foundation

/// Minimize or close windows for role switching (PRD V1 §7, V3).
enum WindowService {
    static func isMenuBarOnly(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .prohibited || app.activationPolicy == .accessory
    }

    static func runningApplication(bundleId: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }
    }

    /// Minimize every regular window for these apps. Never terminates.
    @discardableResult
    static func minimizeWindows(bundleIds: Set<String>) -> Set<String> {
        var failed = Set<String>()
        for bundleId in bundleIds {
            guard let app = runningApplication(bundleId: bundleId) else { continue }
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            if AccessibilityWindowControl.isTrusted() {
                if !AccessibilityWindowControl.minimizeWindows(for: pid) {
                    app.hide()
                }
            } else {
                app.hide()
            }
            if AccessibilityWindowControl.hasOnScreenNormalWindow(for: pid) {
                failed.insert(bundleId)
            }
        }
        return failed
    }

    static func displayNames(for bundleIds: Set<String>) -> [String] {
        bundleIds.map { LaunchService.displayName(bundleId: $0) }.sorted()
    }
}
