import AppKit
import Foundation

/// One Terminal window per role, one tab per configured tab (PRD V5).
enum TerminalStartupService {
    static func markerToken(tabId: UUID) -> String {
        "Mevin·\(tabId.uuidString.uppercased())"
    }

    static func roleWindowToken(profileId: UUID) -> String {
        "Mevin·Role·\(profileId.uuidString.uppercased())"
    }

    static func tabMarkedTitle(roleName: String, tab: TerminalTab) -> String {
        let cmd = tab.trimmedCommand
        let displayCommand: String
        if cmd.isEmpty {
            displayCommand = "shell"
        } else if cmd.count > 48 {
            displayCommand = String(cmd.prefix(45)) + "…"
        } else {
            displayCommand = cmd
        }
        let role = roleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleLabel = role.isEmpty ? "Role" : role
        return "Mevin · \(roleLabel) · \(displayCommand) · \(markerToken(tabId: tab.id))"
    }

    static func roleWindowTitle(roleName: String, profileId: UUID) -> String {
        let role = roleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleLabel = role.isEmpty ? "Role" : role
        return "Mevin · \(roleLabel) · \(roleWindowToken(profileId: profileId))"
    }

    static func failureLabel(command: String, reason: String) -> String {
        let label = command.isEmpty ? "tab" : command
        return "Couldn't run: \(label) (\(reason))"
    }

    /// Role start for the Terminal row (PRD V5, V6 1b/1c).
    ///
    /// For each tab, in order: a tab the user started by hand in the same folder
    /// with the same program counts as done; a tab Mevin marked earlier is
    /// brought forward and its command re-run only if it has stopped; anything
    /// else opens as a new tab in the role's window (created on first need).
    /// Windows are addressed by Terminal's window id, which, unlike the window
    /// index, doesn't change when a window is brought to the front.
    @MainActor
    static func reuseOrRunTabs(
        roleName: String,
        profileId: UUID,
        tabs: [TerminalTab]
    ) async -> [String] {
        guard !tabs.isEmpty else { return [] }

        var failures: [String] = []
        var runnable: [TerminalTab] = []
        for tab in tabs {
            if pathValidationFailure(for: tab) != nil {
                failures.append(failureLabel(command: tab.trimmedCommand, reason: "folder missing"))
            } else {
                runnable.append(tab)
            }
        }
        guard !runnable.isEmpty else { return failures }

        let terminalWasRunning = LaunchService.isRunning(bundleId: Constants.terminalBundleID)
        let scan = terminalWasRunning ? scanTabs() : []
        let processes = terminalWasRunning ? processList() : []
        let roleTokens = Set(tabs.map { markerToken(tabId: $0.id) })
        var roleWindowId = scan.first { row in roleTokens.contains { row.title.contains($0) } }?.windowId
        var broughtForward = Set<Int>()

        for tab in runnable {
            let token = markerToken(tabId: tab.id)

            if let marked = scan.first(where: { $0.title.contains(token) }) {
                bringForward(windowId: marked.windowId, tabIndex: marked.tabIndex, done: &broughtForward)
                if !tab.trimmedCommand.isEmpty, !marked.busy {
                    if !runInTab(windowId: marked.windowId, tabIndex: marked.tabIndex, tab: tab, roleName: roleName) {
                        failures.append(failureLabel(command: tab.trimmedCommand, reason: "couldn't re-run"))
                    }
                }
                continue
            }

            if let mine = scan.first(where: { row in
                !row.title.contains("Mevin·") && userTabMatches(row: row, tab: tab, processes: processes)
            }) {
                bringForward(windowId: mine.windowId, tabIndex: mine.tabIndex, done: &broughtForward)
                continue
            }

            if let windowId = roleWindowId {
                if openTab(inWindowId: windowId, tab: tab, roleName: roleName) { continue }
                if openWindow(tab: tab, roleName: roleName, reuseLaunchWindow: false) == nil {
                    failures.append(failureLabel(command: tab.trimmedCommand, reason: "Terminal couldn't open it"))
                }
                continue
            }

            if let windowId = openWindow(tab: tab, roleName: roleName, reuseLaunchWindow: !terminalWasRunning) {
                roleWindowId = windowId
            } else {
                failures.append(failureLabel(command: tab.trimmedCommand, reason: "Terminal couldn't open it"))
            }
        }

        return failures
    }

    private static func pathValidationFailure(for tab: TerminalTab) -> String? {
        let path = ProfileItem.effectiveTerminalPath(for: tab)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return "missing"
        }
        return nil
    }

    /// Typed into the tab's own shell rather than wrapped in a one-off shell, so
    /// when the command stops the tab is still there to re-run it in (V6 1c).
    static func commandLine(for tab: TerminalTab) -> String {
        let path = ProfileItem.effectiveTerminalPath(for: tab)
        let cmd = tab.trimmedCommand
        if cmd.isEmpty {
            return "cd " + path.shellQuoted
        }
        return "cd " + path.shellQuoted + " && " + cmd
    }

    // MARK: - Opening

    /// New window running the tab. When Terminal was just launched it opens its
    /// own default window; that one is used instead of adding a second window.
    /// Returns the new window's id.
    private static func openWindow(tab: TerminalTab, roleName: String, reuseLaunchWindow: Bool) -> Int? {
        let line = escapeForAppleScript(commandLine(for: tab))
        let title = escapeForAppleScript(tabMarkedTitle(roleName: roleName, tab: tab))
        let reuse = reuseLaunchWindow ? "true" : "false"
        let source = """
        tell application "Terminal"
            activate
            set target to missing value
            if \(reuse) then
                repeat 30 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                end repeat
                if (count of windows) is 1 then
                    if (count of tabs of window 1) is 1 and not (busy of tab 1 of window 1) then
                        set target to tab 1 of window 1
                    end if
                end if
            end if
            if target is missing value then
                set target to do script "\(line)"
            else
                do script "\(line)" in target
            end if
            delay 0.2
            try
                set custom title of target to "\(title)"
            end try
            return id of front window
        end tell
        """
        guard let result = runAppleScript(source), result.int32Value > 0 else { return nil }
        return Int(result.int32Value)
    }

    /// Opens a real new tab (Cmd+T through System Events, which needs
    /// Accessibility) in the given window and runs the tab there. Returns false
    /// when no new tab appeared, so the caller can fall back to a new window.
    private static func openTab(inWindowId windowId: Int, tab: TerminalTab, roleName: String) -> Bool {
        let line = escapeForAppleScript(commandLine(for: tab))
        let title = escapeForAppleScript(tabMarkedTitle(roleName: roleName, tab: tab))
        let source = """
        tell application "Terminal"
            activate
            set w to window id \(windowId)
            set miniaturized of w to false
            set index of w to 1
            set tabsBefore to count of tabs of w
        end tell
        delay 0.2
        tell application "System Events" to keystroke "t" using command down
        set opened to false
        repeat 20 times
            delay 0.1
            tell application "Terminal" to set nowCount to count of tabs of window id \(windowId)
            if nowCount > tabsBefore then
                set opened to true
                exit repeat
            end if
        end repeat
        if not opened then return "fail"
        tell application "Terminal"
            set t to selected tab of window id \(windowId)
            do script "\(line)" in t
            delay 0.2
            try
                set custom title of t to "\(title)"
            end try
        end tell
        return "ok"
        """
        return runAppleScript(source)?.stringValue == "ok"
    }

    private static func runInTab(windowId: Int, tabIndex: Int, tab: TerminalTab, roleName: String) -> Bool {
        let line = escapeForAppleScript(commandLine(for: tab))
        let title = escapeForAppleScript(tabMarkedTitle(roleName: roleName, tab: tab))
        let source = """
        tell application "Terminal"
            set t to tab \(tabIndex) of window id \(windowId)
            do script "\(line)" in t
            try
                set custom title of t to "\(title)"
            end try
        end tell
        """
        return runAppleScript(source) != nil
    }

    /// Restores the window if minimized, brings it to the front and selects the tab.
    private static func bringForward(windowId: Int, tabIndex: Int, done: inout Set<Int>) {
        let selectTab = done.contains(windowId) ? "" : "set selected tab of w to tab \(tabIndex) of w"
        done.insert(windowId)
        let source = """
        tell application "Terminal"
            activate
            set w to window id \(windowId)
            set miniaturized of w to false
            set index of w to 1
            \(selectTab)
        end tell
        """
        _ = runAppleScript(source)
    }

    // MARK: - Reading what's open

    struct TabRow {
        var windowId: Int
        var tabIndex: Int
        var busy: Bool
        var title: String
        var tty: String
    }

    /// Every tab in every Terminal window, including minimized ones.
    private static func scanTabs() -> [TabRow] {
        let source = """
        set out to ""
        set sep to character id 9
        tell application "Terminal"
            repeat with w in windows
                set wid to id of w
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    set ttl to ""
                    try
                        set ttl to custom title of t as text
                    end try
                    set out to out & wid & sep & ti & sep & (busy of t as text) & sep & (tty of t) & sep & ttl & linefeed
                end repeat
            end repeat
        end tell
        return out
        """
        guard let text = runAppleScript(source)?.stringValue else { return [] }
        var rows: [TabRow] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 4, let wid = Int(parts[0]), let ti = Int(parts[1]) else { continue }
            rows.append(
                TabRow(
                    windowId: wid,
                    tabIndex: ti,
                    busy: parts[2] == "true",
                    title: parts.count > 4 ? String(parts[4]) : "",
                    tty: String(parts[3])
                )
            )
        }
        return rows
    }

    private static func userTabMatches(
        row: TabRow,
        tab: TerminalTab,
        processes: [TerminalTabMatcher.ProcessRow]
    ) -> Bool {
        guard let front = TerminalTabMatcher.foreground(tty: row.tty, in: processes),
              let cwd = workingFolder(pid: front.pid)
        else { return false }
        return TerminalTabMatcher.tabMatches(tab: tab, cwd: cwd, processArgs: front.args)
    }

    private static func processList() -> [TerminalTabMatcher.ProcessRow] {
        guard let text = run("/bin/ps", ["-A", "-o", "pid=,stat=,tty=,args="]) else { return [] }
        return TerminalTabMatcher.parseProcessList(text)
    }

    private static func workingFolder(pid: Int32) -> String? {
        guard let text = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting: a full pipe would otherwise stall the process.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func escapeForAppleScript(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result
    }
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
