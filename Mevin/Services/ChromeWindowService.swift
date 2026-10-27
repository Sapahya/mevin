import AppKit
import ApplicationServices
import Foundation

/// Recognises and reuses Chrome windows for a profile (PRD V6 1a, V7 Change 3).
///
/// Windows are addressed by Chrome's own AppleScript window id, which stays the
/// same while the window lives and includes minimized and off-desktop windows.
/// A window's profile is read from that same window's toolbar profile button
/// via Accessibility, matched to the AppleScript window by title and position.
enum ChromeWindowService {
    struct ReuseResult {
        var success: Bool
        var weakReuseWarning: String?
    }

    /// Shown when Chrome's windows exist but none of their profiles could be
    /// read, so Chrome was asked to open the profile (it may add a window).
    static let unconfirmedWindowWarning = "Couldn't confirm Chrome profile window; asked Chrome to open the profile."

    /// One Chrome window as AppleScript reports it.
    struct ChromeWindow: Equatable {
        var id: Int
        var name: String
        var bounds: CGRect
        var minimized: Bool
    }

    static func chromePID() -> pid_t? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == ChromeService.chromeBundleID
        })?.processIdentifier
    }

    /// Versioned so bindings written by older builds are never mistaken for
    /// current ones. v1 stored macOS window numbers; v2 could bind a window of
    /// the wrong profile (it read the Back button as the profile name).
    static let bindingKeyPrefix = "v3|"

    static func bindingKey(profileId: UUID, directory: String) -> String {
        "\(bindingKeyPrefix)\(profileId.uuidString.uppercased())|\(directory)"
    }

    static func isCurrentBindingKey(_ key: String) -> Bool {
        key.hasPrefix(bindingKeyPrefix)
    }

    // MARK: - Reading windows

    /// Every normal Chrome window, front to back, including minimized ones.
    static func windows() -> [ChromeWindow] {
        guard LaunchService.isRunning(bundleId: ChromeService.chromeBundleID) else { return [] }
        let source = """
        set out to ""
        set sep to character id 9
        tell application "Google Chrome"
            repeat with w in windows
                if mode of w is "normal" then
                    set b to bounds of w
                    set out to out & (id of w as text) & sep & (minimized of w as text) & sep & (item 1 of b as text) & sep & (item 2 of b as text) & sep & (item 3 of b as text) & sep & (item 4 of b as text) & sep & (name of w as text) & linefeed
                end if
            end repeat
        end tell
        return out
        """
        guard let text = runAppleScript(source)?.stringValue else {
            ChromeDebugLog.log("windows: AppleScript returned nothing (Automation denied or error)")  // DEBUG-CHROME-LOG
            return []
        }
        let parsedForLog = parseWindows(text)  // DEBUG-CHROME-LOG
        ChromeDebugLog.log("windows: \(parsedForLog.count) -> " + parsedForLog.map { "id=\($0.id) min=\($0.minimized) bounds=\($0.bounds) title=\"\($0.name)\"" }.joined(separator: " | "))  // DEBUG-CHROME-LOG
        return parseWindows(text)
    }

    static func parseWindows(_ text: String) -> [ChromeWindow] {
        var result: [ChromeWindow] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false)
            guard parts.count == 7,
                  let id = Int(parts[0]),
                  let left = Double(parts[2]), let top = Double(parts[3]),
                  let right = Double(parts[4]), let bottom = Double(parts[5])
            else { continue }
            result.append(
                ChromeWindow(
                    id: id,
                    name: String(parts[6]),
                    bounds: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                    minimized: parts[1] == "true"
                )
            )
        }
        return result
    }

    /// Profile names read from each window's own toolbar, keyed by window id.
    /// Windows whose Accessibility element can't be found are left out.
    static func profileNames(for windows: [ChromeWindow]) -> [Int: String] {
        guard !windows.isEmpty, let pid = chromePID() else { return [:] }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else {
            ChromeDebugLog.log("profileNames: could not read Chrome AX windows (Accessibility?) trusted=\(AXIsProcessTrusted())")  // DEBUG-CHROME-LOG
            return [:]
        }

        let described = axWindows.map { element in
            (element: element, title: stringAttribute(element, kAXTitleAttribute), frame: frame(of: element))
        }
        var names: [Int: String] = [:]
        var used = Set<Int>()
        for window in windows {
            guard let index = matchIndex(
                for: window,
                in: described.map { ($0.title, $0.frame) },
                excluding: used
            ) else {
                ChromeDebugLog.log("profileNames: window id=\(window.id) NOT matched to any AX window; AX titles=\(described.map { $0.title ?? "nil" })")  // DEBUG-CHROME-LOG
                continue
            }
            used.insert(index)
            let returnedForLog = profileName(fromToolbar: toolbarButtons(in: described[index].element))  // DEBUG-CHROME-LOG
            ChromeDebugLog.log("profileNames: window id=\(window.id) -> AX[\(index)] title=\"\(described[index].title ?? "nil")\" profile button read as \(returnedForLog.map { "\"\($0)\"" } ?? "nil")")  // DEBUG-CHROME-LOG
            // The title ends with Chrome's name for the profile whenever more
            // than one profile exists; the toolbar button can show a greeting
            // or a sync state instead, so it's only the fallback.
            if let name = described[index].title.flatMap(profileName(fromWindowTitle:))
                ?? profileName(fromToolbar: toolbarButtons(in: described[index].element)) {
                names[window.id] = name
            }
        }
        ChromeDebugLog.log("profileNames: result \(names)")  // DEBUG-CHROME-LOG
        return names
    }

    /// Pairs an AppleScript window with an Accessibility window: same title and
    /// same frame first, then same frame alone, then same title alone (a
    /// minimized window can report a different frame).
    static func matchIndex(
        for window: ChromeWindow,
        in candidates: [(title: String?, frame: CGRect?)],
        excluding used: Set<Int>
    ) -> Int? {
        func close(_ a: CGRect?, _ b: CGRect) -> Bool {
            guard let a else { return false }
            return abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
                && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
        }
        // Accessibility titles add " - Google Chrome – [profile]" to the page title.
        func sameTitle(_ axTitle: String?) -> Bool {
            guard let axTitle else { return false }
            return axTitle == window.name || axTitle.hasPrefix(window.name + " - ")
        }
        let open = candidates.indices.filter { !used.contains($0) }
        if let i = open.first(where: { sameTitle(candidates[$0].title) && close(candidates[$0].frame, window.bounds) }) {
            return i
        }
        let byFrame = open.filter { close(candidates[$0].frame, window.bounds) }
        if byFrame.count == 1 { return byFrame[0] }
        let byTitle = open.filter { sameTitle(candidates[$0].title) }
        if byTitle.count == 1 { return byTitle[0] }
        return nil
    }

    /// Chrome's real profile name for its front window, e.g. right after
    /// "Detect profile" while Chrome sits on the detected profile.
    static func frontWindowProfileName() -> String? {
        guard let front = windows().first else { return nil }
        return profileNames(for: [front])[front.id]
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: size)
    }

    static func debugButtons(in element: AXUIElement, depth: Int = 0) -> [String] {  // DEBUG-CHROME-LOG
        guard depth < 30 else { return [] }  // DEBUG-CHROME-LOG
        var out: [String] = []  // DEBUG-CHROME-LOG
        let role = stringAttribute(element, kAXRoleAttribute) ?? "?"  // DEBUG-CHROME-LOG
        if role == "AXButton" || role == "AXPopUpButton" || role == "AXMenuButton" {  // DEBUG-CHROME-LOG
            let title = stringAttribute(element, kAXTitleAttribute) ?? ""  // DEBUG-CHROME-LOG
            let desc = stringAttribute(element, kAXDescriptionAttribute) ?? ""  // DEBUG-CHROME-LOG
            let help = stringAttribute(element, kAXHelpAttribute) ?? ""  // DEBUG-CHROME-LOG
            if !title.isEmpty || !desc.isEmpty || !help.isEmpty {  // DEBUG-CHROME-LOG
                out.append("\(role)[t=\"\(title)\" d=\"\(desc)\" h=\"\(help)\"]")  // DEBUG-CHROME-LOG
            }  // DEBUG-CHROME-LOG
        }  // DEBUG-CHROME-LOG
        var childrenRef: CFTypeRef?  // DEBUG-CHROME-LOG
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,  // DEBUG-CHROME-LOG
           let children = childrenRef as? [AXUIElement] {  // DEBUG-CHROME-LOG
            for child in children where out.count < 40 {  // DEBUG-CHROME-LOG
                out.append(contentsOf: debugButtons(in: child, depth: depth + 1))  // DEBUG-CHROME-LOG
            }  // DEBUG-CHROME-LOG
        }  // DEBUG-CHROME-LOG
        return out  // DEBUG-CHROME-LOG
    }  // DEBUG-CHROME-LOG


    /// One button from a window's toolbar, in on-screen order.
    struct ToolbarButton: Equatable {
        var role: String
        var title: String
        var description: String

        var label: String {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedTitle.isEmpty ? description.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedTitle
        }

        /// Chrome's app menu ("Customize and control Google Chrome").
        var isAppMenu: Bool {
            role != (kAXButtonRole as String) && (label == "Chrome" || label == "Google Chrome")
        }
    }

    /// Titles of Chrome's own toolbar commands. None of them is ever a profile.
    static let toolbarCommandTitles: Set<String> = [
        "Back", "Forward", "Reload", "Stop", "Home", "Extensions", "Bookmark this tab",
        "Edit bookmark for this tab", "View site information", "Side panel", "Downloads",
        "New Tab", "Search tabs", "Tab search", "Chrome", "Google Chrome", "Close", "Minimize", "Zoom"
    ]

    /// What Chrome's profile button shows for a while instead of the name: a
    /// greeting on a new window ("Hi, Toshit") or the sync state.
    static func isTransientProfileLabel(_ label: String) -> Bool {
        label.hasPrefix("Hi, ") || ["Paused", "Sync paused", "Error", "Verify it's you"].contains(label)
    }

    /// A label that can be a profile name: not empty, not a toolbar command and
    /// not a greeting or sync state.
    static func isProfileName(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !toolbarCommandTitles.contains(trimmed) && !isTransientProfileLabel(trimmed)
    }

    /// Chrome's name for a window's profile from its Accessibility title,
    /// "[page] - Google Chrome – [profile]". Nil when Chrome has only one
    /// profile (no suffix).
    static func profileName(fromWindowTitle title: String) -> String? {
        guard let range = title.range(of: "Google Chrome – ", options: .backwards) else { return nil }
        let name = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return isProfileName(name) ? name : nil
    }

    /// The profile button sits right before Chrome's app menu button. If that
    /// layout isn't found, or the label looks like a command, the profile is
    /// unknown (nil) rather than guessed.
    static func profileName(fromToolbar buttons: [ToolbarButton]) -> String? {
        let named = buttons.filter { !$0.label.isEmpty }
        guard let menuIndex = named.lastIndex(where: \.isAppMenu), menuIndex > 0 else { return nil }
        let label = named[menuIndex - 1].label
        return isProfileName(label) ? label : nil
    }

    /// Buttons in the window's toolbar area, front to back. Web page content is
    /// skipped: it is slow to walk and never holds Chrome's own buttons.
    private static func toolbarButtons(in element: AXUIElement, depth: Int = 0) -> [ToolbarButton] {
        guard depth < 30, let role = stringAttribute(element, kAXRoleAttribute), role != "AXWebArea" else { return [] }
        var result: [ToolbarButton] = []
        if role == kAXButtonRole as String || role == kAXPopUpButtonRole as String || role == kAXMenuButtonRole as String {
            result.append(
                ToolbarButton(
                    role: role,
                    title: stringAttribute(element, kAXTitleAttribute) ?? "",
                    description: stringAttribute(element, kAXDescriptionAttribute) ?? ""
                )
            )
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return result }
        for child in children {
            result.append(contentsOf: toolbarButtons(in: child, depth: depth + 1))
        }
        return result
    }

    // MARK: - Acting on a window

    /// Restores the window if minimized and brings it to the front.
    @MainActor
    static func bringForward(windowId: Int) {
        _ = runAppleScript("""
        tell application "Google Chrome"
            set w to window id "\(windowId)"
            set minimized of w to false
            set index of w to 1
            activate
        end tell
        """)
        LaunchService.activate(bundleId: ChromeService.chromeBundleID)
    }

    // MARK: - Role start

    enum ReuseDecision: Equatable {
        case reuse(Int)
        case open
    }

    /// A window is reused only when its toolbar shows this role's profile
    /// name: the remembered window first, then any other. Remembered windows
    /// are checked every time, since Chrome reuses window ids after a relaunch.
    /// Without a known name nothing can be confirmed, so Chrome opens the
    /// profile itself. Never "the front window".
    static func decide(windowIds: [Int], names: [Int: String], wanted: String?, bound: Int?) -> ReuseDecision {
        guard let wanted, isProfileName(wanted) else { return .open }
        func matches(_ id: Int) -> Bool {
            names[id]?.localizedCaseInsensitiveCompare(wanted) == .orderedSame
        }
        if let bound, windowIds.contains(bound), matches(bound) { return .reuse(bound) }
        if let match = windowIds.first(where: matches) { return .reuse(match) }
        return .open
    }

    /// The window Chrome opened for the profile. One new window is that
    /// window. Several (Chrome restoring other profiles' windows on launch)
    /// are told apart only by the known name; otherwise none is assumed.
    static func pickOpenedWindow(newIds: [Int], names: [Int: String], wanted: String?) -> Int? {
        if let wanted, isProfileName(wanted),
           let match = newIds.first(where: { names[$0]?.localizedCaseInsensitiveCompare(wanted) == .orderedSame }) {
            return match
        }
        return newIds.count == 1 ? newIds[0] : nil
    }

    /// Reuses the role's profile window, or has Chrome open the profile.
    /// Links go only into the confirmed window, and only those not already open.
    @MainActor
    static func openOrReuseProfileWindow(
        profileId: UUID,
        directory: String,
        urls: [String],
        chromeProfileName: String?,
        bindings: inout [String: Int],
        captureProfileName: (String) -> Void
    ) async -> ReuseResult {
        let key = bindingKey(profileId: profileId, directory: directory)
        let current = windows()
        let names = profileNames(for: current)
        ChromeDebugLog.log("openOrReuse: START role=\(profileId) directory=\"\(directory)\" urls=\(urls.count) savedToolbarName=\(chromeProfileName.map { "\"\($0)\"" } ?? "nil") boundWindow=\(bindings[key].map(String.init) ?? "nil")")  // DEBUG-CHROME-LOG

        let decision = decide(
            windowIds: current.map(\.id),
            names: names,
            wanted: chromeProfileName,
            bound: bindings[key]
        )
        ChromeDebugLog.log("openOrReuse: decision \(decision)")  // DEBUG-CHROME-LOG
        if case .reuse(let id) = decision {
            bindings[key] = id
            useWindow(id, urls: urls, names: names, capture: captureProfileName)
            return ReuseResult(success: true, weakReuseWarning: nil)
        }
        bindings[key] = nil

        // Windows exist but none could be read (Accessibility off, or Chrome
        // changed its toolbar): Chrome may add a window for a profile that
        // already has one, so the start report says why.
        let warning = !current.isEmpty && names.isEmpty ? unconfirmedWindowWarning : nil

        let before = Set(current.map(\.id))
        guard ChromeService.openProfile(directory: directory, urls: urls) else {
            return ReuseResult(success: false, weakReuseWarning: nil)
        }

        var fresh: [ChromeWindow] = []
        for _ in 0 ..< 20 {
            try? await Task.sleep(for: .milliseconds(150))
            fresh = windows().filter { !before.contains($0.id) }
            if !fresh.isEmpty { break }
        }
        // Give a cold-started Chrome a moment to finish restoring windows and
        // drawing its toolbar before reading profile names.
        var freshNames: [Int: String] = [:]
        for _ in 0 ..< 5 where !fresh.isEmpty {
            try? await Task.sleep(for: .milliseconds(200))
            fresh = windows().filter { !before.contains($0.id) }
            freshNames = profileNames(for: fresh)
            if freshNames.count == fresh.count { break }
        }

        let chosen = pickOpenedWindow(newIds: fresh.map(\.id), names: freshNames, wanted: chromeProfileName)
        ChromeDebugLog.log("openOrReuse: after openProfile new windows=\(fresh.map(\.id)) names=\(freshNames) chosen=\(chosen.map(String.init) ?? "none (Chrome placed the tabs itself)")")  // DEBUG-CHROME-LOG
        // No new window, or several that can't be told apart: Chrome placed
        // the links in the profile's own window, so nothing is bound or saved.
        guard let chosen else { return ReuseResult(success: true, weakReuseWarning: warning) }
        bindings[key] = chosen
        useWindow(chosen, urls: urls, names: freshNames, capture: captureProfileName)
        return ReuseResult(success: true, weakReuseWarning: warning)
    }

    @MainActor
    private static func useWindow(_ id: Int, urls: [String], names: [Int: String], capture: (String) -> Void) {
        bringForward(windowId: id)
        _ = ChromeService.openMissingTabs(urls: urls, windowId: id)
        ChromeDebugLog.log("useWindow: used window \(id); captureProfileName(\(names[id].map { "\"\($0)\"" } ?? "nil, nothing saved"))")  // DEBUG-CHROME-LOG
        if let name = names[id], isProfileName(name) {
            capture(name)
        }
    }

    // MARK: - Switching away (PRD V10 Change 2, V11 Change 2)

    enum OldWindowAction: Equatable {
        case close
        case minimize
    }

    /// The old role's profile windows. A window counts only when Mevin is sure:
    /// its toolbar shows the old profile's name, or Mevin opened it for the old
    /// role (its binding) and nothing read from it says otherwise. Unreadable
    /// windows Mevin didn't open are left alone, as is `keep` (the new role's
    /// window) and anything showing the new profile's name. Two profiles with
    /// the same name can't be told apart by name, so only the binding counts.
    static func oldProfileWindows(
        windowIds: [Int],
        names: [Int: String],
        oldName: String?,
        oldBound: Int?,
        newName: String?,
        keep: Int?
    ) -> [Int] {
        func same(_ a: String?, _ b: String?) -> Bool {
            guard let a, let b else { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedSame
        }
        let usableOld = oldName.flatMap { isProfileName($0) ? $0 : nil }
        let namesDiffer = !same(usableOld, newName)
        return windowIds.filter { id in
            guard id != keep else { return false }
            // Same name in both roles: names can't tell them apart.
            guard namesDiffer else { return id == oldBound }
            if let read = names[id] {
                if same(read, newName) { return false }
                // A remembered id read as another profile is one Chrome reused.
                return same(read, usableOld)
            }
            return id == oldBound
        }
    }

    /// Closes or minimizes the old role's profile windows once the new role's
    /// window is open. Returns the windows acted on. Chrome itself never quits.
    @MainActor
    static func retireOldProfileWindows(
        oldName: String?,
        oldBound: Int?,
        newName: String?,
        keep: Int?,
        action: OldWindowAction
    ) -> [Int] {
        let current = windows()
        let names = profileNames(for: current)
        let targets = oldProfileWindows(
            windowIds: current.map(\.id),
            names: names,
            oldName: oldName,
            oldBound: oldBound,
            newName: newName,
            keep: keep
        )
        ChromeDebugLog.log("retireOld: oldName=\(oldName ?? "nil") oldBound=\(oldBound.map(String.init) ?? "nil") newName=\(newName ?? "nil") keep=\(keep.map(String.init) ?? "nil") names=\(names) targets=\(targets) action=\(action)")  // DEBUG-CHROME-LOG
        let command = action == .close ? "close w" : "set minimized of w to true"
        return targets.filter { id in
            runAppleScript("""
            tell application "Google Chrome"
                set w to window id "\(id)"
                \(command)
            end tell
            """) != nil
        }
    }

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result
    }
}
