import AppKit
import Foundation

/// Accumulates frontmost time per app. No permissions: this is the same
/// `NSWorkspace` notification the Dock already uses.
@MainActor
final class FocusTracker {
    private(set) var seconds: [String: Int] = [:]
    private var currentBundleId: String?
    private var lastChange: Date?
    private var observer: NSObjectProtocol?

    func start(initial: [String: Int] = [:]) {
        stop()
        seconds = initial
        currentBundleId = accepted(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        lastChange = Date()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.note(app?.bundleIdentifier)
            }
        }
    }

    func flush() {
        guard let lastChange, let currentBundleId else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(lastChange)))
        seconds[currentBundleId, default: 0] += elapsed
        self.lastChange = Date()
    }

    func stop() {
        flush()
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        currentBundleId = nil
        lastChange = nil
    }

    private func note(_ bundleId: String?) {
        flush()
        currentBundleId = accepted(bundleId)
        lastChange = Date()
    }

    private func accepted(_ bundleId: String?) -> String? {
        guard let bundleId, !Constants.ignoredBundleIDs.contains(bundleId) else { return nil }
        return bundleId
    }
}
