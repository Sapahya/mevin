import AppKit
import Foundation

/// Which running apps the switch panel lists (PRD V10 Changes 1 and 3), and
/// which apps each "Quit" button on the end question and the footer quits
/// (Changes 4 and 5).
enum KeepOpenPanelHelper {
    struct Row: Identifiable, Hashable {
        var bundleId: String
        var name: String

        var id: String { bundleId }
    }

    /// A running app Mevin may list or quit. Untouchable apps never become one.
    struct RunningApp: Hashable {
        var bundleId: String
        var name: String
        /// Has a window that isn't minimized on the current desktop.
        var onScreen: Bool
        /// 0 for the front-most app on screen; nil when not on screen.
        var frontRank: Int? = nil
    }

    /// Every running dock app except the untouchable ones: Mevin, Finder, the
    /// Always open list and menu bar apps (Constants.ignoredBundleIDs; menu bar
    /// only apps never appear as dock apps).
    static func listedApps(neverClose: Set<String>) -> [RunningApp] {
        var excluded = neverClose
        excluded.formUnion(Constants.ignoredBundleIDs)
        excluded.insert(Constants.finderBundleID)
        excluded.insert(Constants.bundleID)
        let ranks = WindowClassifier.frontToBackOwnerPIDs()
        return WindowClassifier.classifyRunningApps(excludingBundleIds: excluded).map { classified in
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: classified.app.bundleId)
                .first?.processIdentifier
            let onScreen = classified.bucket == .onScreen
            return RunningApp(
                bundleId: classified.app.bundleId,
                name: classified.app.name,
                onScreen: onScreen,
                frontRank: onScreen ? pid.flatMap { ranks.firstIndex(of: $0) } : nil
            )
        }
    }

    /// Case D: on screen and not in the next role. Minimized apps (case E) and
    /// the next role's own apps (cases B and C) are never listed. Front-most first.
    static func switchRows(running: [RunningApp], nextRole owned: Set<String>) -> [Row] {
        running
            .filter { $0.onScreen && !owned.contains($0.bundleId) }
            .sorted(by: frontMostFirst)
            .map { Row(bundleId: $0.bundleId, name: $0.name) }
    }

    /// "Quit [Role]'s apps": every running app listed in the role, minimized
    /// ones included.
    static func roleApps(running: [RunningApp], role owned: Set<String>) -> Set<String> {
        Set(running.filter { owned.contains($0.bundleId) }.map(\.bundleId))
    }

    /// "Quit all on screen" and the footer list: apps on screen on the
    /// current desktop. Minimized apps stay running.
    static func onScreenRows(running: [RunningApp]) -> [Row] {
        running
            .filter(\.onScreen)
            .sorted(by: frontMostFirst)
            .map { Row(bundleId: $0.bundleId, name: $0.name) }
    }

    /// Primary button on the switch panel: always says what's about to happen.
    static func primaryLabel(quitCount: Int, starting: Bool) -> String {
        let verb = starting ? "start" : "switch"
        switch quitCount {
        case 0: return starting ? "Start" : "Switch"
        case 1: return "Quit 1 app and \(verb)"
        default: return "Quit \(quitCount) apps and \(verb)"
        }
    }

    private static func frontMostFirst(_ a: RunningApp, _ b: RunningApp) -> Bool {
        switch (a.frontRank, b.frontRank) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

enum SwitchDebugLog {  // DEBUG-SWITCH-LOG
    static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Mevin/switch-debug.log")  // DEBUG-SWITCH-LOG
    static func log(_ message: String) {  // DEBUG-SWITCH-LOG
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])  // DEBUG-SWITCH-LOG
        guard let data = "[\(stamp)] \(message)\n".data(using: .utf8) else { return }  // DEBUG-SWITCH-LOG
        if let handle = try? FileHandle(forWritingTo: url) {  // DEBUG-SWITCH-LOG
            handle.seekToEndOfFile()  // DEBUG-SWITCH-LOG
            handle.write(data)  // DEBUG-SWITCH-LOG
            try? handle.close()  // DEBUG-SWITCH-LOG
        } else {  // DEBUG-SWITCH-LOG
            try? data.write(to: url)  // DEBUG-SWITCH-LOG
        }  // DEBUG-SWITCH-LOG
    }  // DEBUG-SWITCH-LOG

    /// Every running app and why the switch panel did or didn't list it.  // DEBUG-SWITCH-LOG
    static func logSwitch(roleName: String, neverClose: Set<String>, owned: Set<String>, listed: [KeepOpenPanelHelper.Row]) {  // DEBUG-SWITCH-LOG
        let onScreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []  // DEBUG-SWITCH-LOG
        let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []  // DEBUG-SWITCH-LOG
        let listedIds = Set(listed.map(\.bundleId))  // DEBUG-SWITCH-LOG
        log("==== switch panel for next role \"\(roleName)\": listed \(listed.map(\.name))")  // DEBUG-SWITCH-LOG
        log("owned by next role: \(owned.sorted())")  // DEBUG-SWITCH-LOG
        for app in NSWorkspace.shared.runningApplications {  // DEBUG-SWITCH-LOG
            let id = app.bundleIdentifier ?? "(no bundle id)"  // DEBUG-SWITCH-LOG
            let name = app.localizedName ?? "?"  // DEBUG-SWITCH-LOG
            let policy: String = app.activationPolicy == .regular ? "regular" : (app.activationPolicy == .accessory ? "accessory" : "prohibited")  // DEBUG-SWITCH-LOG
            if app.activationPolicy == .prohibited { continue }  // DEBUG-SWITCH-LOG (background helpers, too many to log)
            let pid = app.processIdentifier  // DEBUG-SWITCH-LOG
            let mine = onScreen.filter { WindowClassifier.windowOwnerPID($0) == pid }  // DEBUG-SWITCH-LOG
            let windowText = mine.map { w -> String in  // DEBUG-SWITCH-LOG
                let layer = w[kCGWindowLayer as String] as? Int ?? -1  // DEBUG-SWITCH-LOG
                let alpha = w[kCGWindowAlpha as String] as? Double ?? -1  // DEBUG-SWITCH-LOG
                let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]  // DEBUG-SWITCH-LOG
                let size = "\(Int(WindowClassifier.numericDimension(b["Width"]) ?? -1))x\(Int(WindowClassifier.numericDimension(b["Height"]) ?? -1))"  // DEBUG-SWITCH-LOG
                let title = w[kCGWindowName as String] as? String ?? ""  // DEBUG-SWITCH-LOG
                return "[\(size) layer=\(layer) alpha=\(alpha) normal=\(WindowClassifier.isNormalWindow(w)) title=\"\(title)\"]"  // DEBUG-SWITCH-LOG
            }.joined(separator: " ")  // DEBUG-SWITCH-LOG
            let allCount = all.filter { WindowClassifier.windowOwnerPID($0) == pid }.count  // DEBUG-SWITCH-LOG
            let reason: String  // DEBUG-SWITCH-LOG
            if listedIds.contains(id) { reason = "LISTED" }  // DEBUG-SWITCH-LOG
            else if app.activationPolicy != .regular { reason = "skipped: not a regular app (\(policy))" }  // DEBUG-SWITCH-LOG
            else if id == Constants.bundleID || id == Constants.finderBundleID { reason = "skipped: Mevin or Finder" }  // DEBUG-SWITCH-LOG
            else if neverClose.contains(id) { reason = "skipped: on Always open list" }  // DEBUG-SWITCH-LOG
            else if Constants.ignoredBundleIDs.contains(id) { reason = "skipped: in ignoredBundleIDs" }  // DEBUG-SWITCH-LOG
            else if owned.contains(id) { reason = "skipped: in next role" }  // DEBUG-SWITCH-LOG
            else if mine.isEmpty { reason = "skipped: no window on this desktop (minimized, hidden or other desktop)" }  // DEBUG-SWITCH-LOG
            else if !mine.contains(where: WindowClassifier.isNormalWindow) { reason = "skipped: on-screen windows all too small (<100x100), not layer 0, or transparent" }  // DEBUG-SWITCH-LOG
            else { reason = "skipped: UNEXPLAINED (on screen, regular, not owned)" }  // DEBUG-SWITCH-LOG
            log("  \(name) <\(id)> policy=\(policy) hidden=\(app.isHidden) windowsAll=\(allCount) onScreen=\(mine.count) \(windowText) => \(reason)")  // DEBUG-SWITCH-LOG
        }  // DEBUG-SWITCH-LOG
    }  // DEBUG-SWITCH-LOG
}  // DEBUG-SWITCH-LOG
