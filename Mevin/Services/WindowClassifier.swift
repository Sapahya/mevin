import AppKit
import CoreGraphics
import Foundation

/// Splits running dock apps into on-screen vs background for Capture (PRD V2).
enum WindowClassifier {
    static let minimumWindowDimension: CGFloat = 100

    enum CaptureBucket: Equatable {
        case onScreen
        case otherOpen
    }

    struct ClassifiedApp: Equatable {
        var app: InstalledApp
        var bucket: CaptureBucket
    }

    /// Running regular apps, split by whether they own a normal window on the current desktop.
    static func classifyRunningApps(excludingBundleIds excluded: Set<String> = Constants.ignoredBundleIDs) -> [ClassifiedApp] {
        let onScreenList = windowList(option: .optionOnScreenOnly)
        let allList = windowList(option: .optionAll)
        let mevinPID = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.bundleID)
            .first?.processIdentifier

        var seen = Set<String>()
        var result: [ClassifiedApp] = []

        for app in LaunchService.foregroundApps() {
            guard seen.insert(app.bundleId).inserted else { continue }
            guard !excluded.contains(app.bundleId) else { continue }
            guard let pid = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == app.bundleId })?
                .processIdentifier else { continue }
            if let mevinPID, pid == mevinPID { continue }

            let onScreen = hasNormalWindow(for: pid, in: onScreenList)
            let bucket: CaptureBucket = onScreen ? .onScreen : .otherOpen
            // Running with no windows at all still lands in otherOpen.
            if !onScreen, !hasNormalWindow(for: pid, in: allList) {
                // No normal windows anywhere — still otherOpen (background / headless UI).
            }
            result.append(ClassifiedApp(app: app, bucket: bucket))
        }

        return result
    }

    /// Owners of normal on-screen windows, front-most first, each listed once.
    static func frontToBackOwnerPIDs() -> [pid_t] {
        var seen = Set<pid_t>()
        return windowList(option: .optionOnScreenOnly).compactMap { window in
            guard isNormalWindow(window), let pid = windowOwnerPID(window), seen.insert(pid).inserted else { return nil }
            return pid
        }
    }

    static func hasNormalWindow(for pid: pid_t, in windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            guard windowOwnerPID(window) == pid else { return false }
            return isNormalWindow(window)
        }
    }

    /// Testable window metadata checks (CGWindowListCopyWindowInfo dictionaries).
    static func isNormalWindow(_ window: [String: Any]) -> Bool {
        if let layer = window[kCGWindowLayer as String] as? Int, layer != 0 { return false }
        if let alpha = window[kCGWindowAlpha as String] as? Double, alpha < 0.01 { return false }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = numericDimension(bounds["Width"]),
              let height = numericDimension(bounds["Height"]) else {
            return false
        }
        return width >= minimumWindowDimension && height >= minimumWindowDimension
    }

    static func numericDimension(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(number.doubleValue)
        case let width as CGFloat:
            return width
        case let width as Double:
            return CGFloat(width)
        case let width as Int:
            return CGFloat(width)
        default:
            return nil
        }
    }

    static func windowOwnerPID(_ window: [String: Any]) -> pid_t? {
        window[kCGWindowOwnerPID as String] as? pid_t
    }

    private static func windowList(option: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
    }
}
