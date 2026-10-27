import AppKit
import Foundation

enum LaunchService {
    static func runningBundleIDs() -> Set<String> {
        Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
    }

    static func isRunning(bundleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    static func displayName(bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleId
    }

    static func applicationURL(bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    /// Role start: every app in the role must end with a visible window (PRD V3).
    @MainActor
    static func ensureRoleAppVisible(bundleId: String) async -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return await launchFresh(bundleId: bundleId)
        }

        if app.isHidden {
            app.unhide()
        }

        let pid = app.processIdentifier
        if !AccessibilityWindowControl.hasOnScreenNormalWindow(for: pid) {
            _ = AccessibilityWindowControl.unminimizeWindows(for: pid)
        }
        if !AccessibilityWindowControl.hasOnScreenNormalWindow(for: pid) {
            _ = requestReopen(bundleId: bundleId)
        }

        app.activate(options: [.activateIgnoringOtherApps])
        return nil
    }

    @MainActor
    private static func launchFresh(bundleId: String) async -> String? {
        guard let url = applicationURL(bundleId: bundleId) else {
            return displayName(bundleId: bundleId)
        }
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return nil
        } catch {
            return displayName(bundleId: bundleId)
        }
    }

    @discardableResult
    static func activate(bundleId: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return false
        }
        if app.isHidden { app.unhide() }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    @discardableResult
    private static func requestReopen(bundleId: String) -> Bool {
        let source = """
        tell application id "\(bundleId)"
            reopen
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    /// A nil `appBundleId` means the folder opens in Finder.
    @MainActor
    static func openFolder(_ path: String, appBundleId: String?) async -> String? {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return (path as NSString).abbreviatingWithTildeInPath
        }

        guard let appBundleId else {
            return NSWorkspace.shared.open(url) ? nil : (path as NSString).lastPathComponent
        }

        guard let appURL = applicationURL(bundleId: appBundleId) else {
            return displayName(bundleId: appBundleId)
        }
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            return nil
        } catch {
            return (path as NSString).lastPathComponent
        }
    }

    /// Always polite. An app with unsaved work puts up its own save dialog, and
    /// is left running rather than forced, because a tidy session is never worth
    /// someone's work.
    static func requestQuit(bundleIds: Set<String>) {
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, bundleIds.contains(id) else { continue }
            app.terminate()
        }
    }

    static func installedApplications() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items where item.pathExtension == "app" {
                guard let bundle = Bundle(url: item),
                      let id = bundle.bundleIdentifier,
                      !seen.contains(id),
                      !Constants.ignoredBundleIDs.contains(id) else { continue }
                seen.insert(id)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? item.deletingPathExtension().lastPathComponent
                result.append(InstalledApp(bundleId: id, name: name, url: item))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Apps with a real UI. The same definition as a row on the Dock.
    static func foregroundApps() -> [InstalledApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier else { return nil }
            let url = app.bundleURL ?? applicationURL(bundleId: id) ?? URL(fileURLWithPath: "/")
            let name = app.localizedName ?? displayName(bundleId: id)
            return InstalledApp(bundleId: id, name: name, url: url)
        }
    }
}

struct InstalledApp: Identifiable, Hashable {
    var bundleId: String
    var name: String
    var url: URL
    var id: String { bundleId }
}

extension NSWorkspace {
    /// Real icons, read locally. Nothing here touches the network.
    func icon(forBundleID bundleId: String) -> NSImage? {
        guard let url = LaunchService.applicationURL(bundleId: bundleId) else { return nil }
        return icon(forFile: url.path)
    }
}
