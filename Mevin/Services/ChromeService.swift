import AppKit
import Foundation

struct ChromeAccount: Identifiable, Hashable {
    var directory: String
    var displayName: String
    /// Chrome's own toolbar profile name, when known. Never the Mevin display label.
    var chromeToolbarName: String? = nil
    var id: String { directory }
}

/// Why Mevin could or could not list Chrome's profiles. The old code returned an
/// empty array for all of these, which is how a kernel-level block stayed
/// invisible until someone tried to use the feature.
enum ChromeProfileLookup: Equatable {
    case ok([ChromeAccount])
    /// Chrome is not on this Mac.
    case notInstalled
    /// Installed, but it has never run, so it has not written its state yet.
    case neverLaunched
    /// macOS refuses to let any third-party app read Chrome's data directory.
    /// Not a permission Mevin can ask for. See `systemBlockExplanation`.
    case blockedBySystem
    /// Present and readable, but not what we expected inside.
    case unreadable(String)

    var accounts: [ChromeAccount] {
        if case .ok(let accounts) = self { return accounts }
        return []
    }
}

enum ChromeDebugLog {  // DEBUG-CHROME-LOG
    static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Mevin/chrome-debug.log")  // DEBUG-CHROME-LOG
    static func log(_ message: String) {  // DEBUG-CHROME-LOG
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime, .withFractionalSeconds])  // DEBUG-CHROME-LOG
        let line = "[\(stamp)] \(message)\n"  // DEBUG-CHROME-LOG
        NSLog("[MevinChromeDebug] %@", message)  // DEBUG-CHROME-LOG
        guard let data = line.data(using: .utf8) else { return }  // DEBUG-CHROME-LOG
        if let handle = try? FileHandle(forWritingTo: url) {  // DEBUG-CHROME-LOG
            handle.seekToEndOfFile()  // DEBUG-CHROME-LOG
            handle.write(data)  // DEBUG-CHROME-LOG
            try? handle.close()  // DEBUG-CHROME-LOG
        } else {  // DEBUG-CHROME-LOG
            try? data.write(to: url)  // DEBUG-CHROME-LOG
        }  // DEBUG-CHROME-LOG
    }  // DEBUG-CHROME-LOG
}  // DEBUG-CHROME-LOG


enum ChromeService {
    static let chromeBundleID = "com.google.Chrome"

    static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
    }

    static var localStateURL: URL {
        dataDirectory.appendingPathComponent("Local State")
    }

    /// macOS 27 extended the `com.apple.macl` protection that guards sandboxed
    /// apps' containers to a hardcoded list of browser data directories,
    /// including Chrome's, binding access to Google's own Team ID. The kernel
    /// denies everyone else with EPERM and no prompt is ever shown, so Full Disk
    /// Access does not help and there is nothing for the user to grant.
    /// Hard constraint (PRD V2): Chrome's profile list is not readable by third-party apps on current macOS.
    static let systemBlockExplanation =
        "macOS blocks every app except Chrome from reading its profile list. Link a profile manually with chrome://version."

    /// `urlForApplication` consults LaunchServices, which is unreliable about
    /// apps it has not seen run, so a miss falls back to looking on disk.
    static func isInstalled() -> Bool {
        if LaunchService.applicationURL(bundleId: chromeBundleID) != nil { return true }
        return installedPath() != nil
    }

    static func installedPath() -> URL? {
        if let url = LaunchService.applicationURL(bundleId: chromeBundleID) { return url }
        let candidates = [
            URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Google Chrome.app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func profiles() -> ChromeProfileLookup {
        guard isInstalled() else { return .notInstalled }

        let data: Data
        do {
            data = try Data(contentsOf: localStateURL)
        } catch let error as NSError {
            if isPermissionDenied(error) { return .blockedBySystem }
            if isMissing(error) {
                // A file the kernel is hiding also reports as missing, so the
                // two are told apart by asking the directory.
                return isDataDirectoryBlocked() ? .blockedBySystem : .neverLaunched
            }
            return .unreadable(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unreadable("Chrome's profile file isn't readable JSON.")
        }
        guard let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else {
            return .unreadable("Chrome's profile file didn't contain a profile list.")
        }

        let accounts = cache.keys.sorted().compactMap { directory -> ChromeAccount? in
            guard let info = cache[directory] as? [String: Any] else { return nil }
            return ChromeAccount(
                directory: directory,
                displayName: displayName(from: info, directory: directory)
            )
        }
        return accounts.isEmpty ? .unreadable("Chrome listed no profiles.") : .ok(accounts)
    }

    /// Distinguishes "Chrome has never run" from "the kernel is hiding the whole
    /// directory", which look identical through `fileExists`.
    private static func isDataDirectoryBlocked() -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)
            return false
        } catch let error as NSError {
            return isPermissionDenied(error)
        }
    }

    /// Foundation wraps the POSIX errno inside a Cocoa error, so both layers are
    /// worth checking before concluding anything about a read failure.
    private static func isPermissionDenied(_ error: NSError) -> Bool {
        matches(error, cocoa: NSFileReadNoPermissionError, posix: [EPERM, EACCES])
    }

    private static func isMissing(_ error: NSError) -> Bool {
        matches(error, cocoa: NSFileNoSuchFileError, posix: [ENOENT])
    }

    private static func matches(_ error: NSError, cocoa: Int, posix: [Int32]) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == cocoa { return true }
        let codes = posix.map(Int.init)
        if error.domain == NSPOSIXErrorDomain && codes.contains(error.code) { return true }
        return error.underlyingErrors.contains { underlying in
            let ns = underlying as NSError
            return ns.domain == NSPOSIXErrorDomain && codes.contains(ns.code)
        }
    }

    private static func displayName(from info: [String: Any], directory: String) -> String {
        for key in ["name", "gaia_name", "user_name"] {
            if let value = info[key] as? String, !value.isEmpty { return value }
        }
        return directory
    }

    static func lastUsedDirectory() -> String? {
        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any]
        else { return nil }
        return profile["last_used"] as? String
    }

    /// Accepts whatever the user pastes: the whole `Profile Path` line copied
    /// from `chrome://version`, a path with a trailing slash, or just the folder
    /// name. All that matters is the final component, which is what Chrome's
    /// `--profile-directory` flag wants.
    static func isLikelyProfileDirectory(_ name: String) -> Bool {
        if name == "Default" { return true }
        let pattern = "^Profile [0-9]+$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func extractProfilePathLine(from text: String) -> String? {
        guard text.localizedCaseInsensitiveContains("profile path") else { return nil }
        if let range = text.range(of: "Profile Path:", options: .caseInsensitive) {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func profileDirectoryName(fromPasted raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "Profile Path:", options: .caseInsensitive) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        let name = text.contains("/") ? (text as NSString).lastPathComponent : text
        // A path ending at the Chrome folder itself means the user copied one
        // level too few; there is no profile named "Chrome".
        guard !name.isEmpty, name != "Chrome" else { return nil }
        return name
    }

    /// Opens `chrome://version` so the user can read the Profile Path for
    /// whichever profile Chrome is currently on. This is the only route left to
    /// discovering a profile's folder name. It goes into the front window, so
    /// it shows the profile the user is looking at; a launch argument would
    /// land in the profile Chrome used last instead.
    @discardableResult
    static func openProfileInfo() -> Bool {
        if LaunchService.isRunning(bundleId: chromeBundleID) {
            let source = """
            tell application "Google Chrome"
                if (count of windows) is 0 then return false
                tell front window to make new tab with properties {URL:"chrome://version"}
                activate
            end tell
            return true
            """
            var error: NSDictionary?
            if let script = NSAppleScript(source: source),
               script.executeAndReturnError(&error).booleanValue, error == nil {
                return true
            }
        }
        return launch(arguments: ["chrome://version"])
    }

    /// True when Chrome's front window shows chrome://version and it has
    /// finished loading.
    static func versionPageLoaded() -> Bool {
        guard LaunchService.isRunning(bundleId: chromeBundleID) else { return false }
        let source = """
        tell application "Google Chrome"
            if (count of windows) is 0 then return false
            set t to active tab of front window
            return (URL of t as text) starts with "chrome://version" and (loading of t) is false
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }

    /// Closes a chrome://version tab Mevin opened for detection.
    @discardableResult
    static func closeVersionPageTab() -> Bool {
        guard isInstalled(), LaunchService.isRunning(bundleId: chromeBundleID) else { return false }
        let source = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t as text
                    if u starts with "chrome://version" then
                        close t
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    /// Opens Chrome's profile management UI so the user can add a profile.
    @discardableResult
    static func openManageProfiles() -> Bool {
        launch(arguments: ["chrome://settings/manageProfile"])
    }

    /// Chrome cannot report which profile a user picked in its own chooser, so
    /// the choice is made in Mevin and handed to Chrome at launch instead.
    /// The links are passed along, so Chrome opens them as the window's tabs
    /// rather than adding an empty new-tab page first (PRD V7 Change 3).
    @discardableResult
    static func openProfile(directory: String, urls: [String]) -> Bool {
        launch(arguments: launchArguments(directory: directory, urls: urls))
    }

    /// Never `--new-window` (it adds an empty tab) and never a URL-less blank.
    static func launchArguments(directory: String, urls: [String]) -> [String] {
        ["--profile-directory=\(directory)"] + urls.filter { !$0.isEmpty }
    }

    /// Adds the links that aren't open yet as tabs in that one window.
    @discardableResult
    static func openMissingTabs(urls: [String], windowId: Int) -> Bool {
        let list = urls.filter { !$0.isEmpty }
        guard !list.isEmpty else { return true }
        let existing = tabURLs(inWindowId: windowId).map(\.url)
        let missing = list.filter { !existing.contains($0) }
        guard !missing.isEmpty else { return true }

        let joined = missing.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        let source = """
        tell application "Google Chrome"
            repeat with u in {\(joined)}
                tell window id "\(windowId)"
                    make new tab with properties {URL:u}
                end tell
            end repeat
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    static func tabURLs(inWindowId windowId: Int) -> [OpenTab] {
        guard isInstalled(), LaunchService.isRunning(bundleId: chromeBundleID) else { return [] }
        let source = """
        set sep to character id 9
        tell application "Google Chrome"
            set out to ""
            repeat with t in tabs of window id "\(windowId)"
              set out to out & (URL of t as text) & sep & (title of t as text) & linefeed
            end repeat
            return out
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue else { return [] }
        return parseTabLines(text)
    }

    private static func parseTabLines(_ text: String) -> [OpenTab] {
        var tabs: [OpenTab] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let url = parts.first, !url.isEmpty else { continue }
            let title = parts.count > 1 ? parts[1] : url
            tabs.append(OpenTab(url: url, title: title))
        }
        return tabs
    }

    /// Starts Chrome with arguments. `open -a … --args` only passes arguments
    /// when it launches the app, so while Chrome is already running its own
    /// executable is called instead: that process hands the arguments to the
    /// running Chrome and exits. No second Chrome stays open (no `open -n`).
    private static func launch(arguments: [String]) -> Bool {
        guard isInstalled() else { return false }
        ChromeDebugLog.log("launch: running=\(LaunchService.isRunning(bundleId: chromeBundleID)) args=\(arguments)")  // DEBUG-CHROME-LOG
        let process = Process()
        if LaunchService.isRunning(bundleId: chromeBundleID),
           let executable = installedPath()?.appendingPathComponent("Contents/MacOS/Google Chrome"),
           FileManager.default.isExecutableFile(atPath: executable.path) {
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                return true
            } catch {
                return false
            }
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Google Chrome", "--args"] + arguments
            ChromeDebugLog.log("launch: via open -a (Chrome not running)")  // DEBUG-CHROME-LOG
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            ChromeDebugLog.log("launch: open -a exit status \(process.terminationStatus)")  // DEBUG-CHROME-LOG
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    struct OpenTab: Equatable, Identifiable {
        var url: String
        var title: String
        var id: String { url }
    }

    /// Open tab URLs from the running Chrome. Automation denial returns an
    /// empty list; the caller must not surface an error.
    static func tabURLs() -> [OpenTab] {
        guard isInstalled(), LaunchService.isRunning(bundleId: chromeBundleID) else { return [] }
        let source = """
        set sep to character id 9
        tell application "Google Chrome"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              set out to out & (URL of t as text) & sep & (title of t as text) & linefeed
            end repeat
          end repeat
          return out
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let executed = script.executeAndReturnError(&error)
        if error != nil { return [] }
        let text = executed.stringValue ?? ""
        var seen = Set<String>()
        var tabs: [OpenTab] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawURL = parts.first else { continue }
            let url = String(rawURL).trimmingCharacters(in: .whitespacesAndNewlines)
            guard url.hasPrefix("http://") || url.hasPrefix("https://") else { continue }
            guard !seen.contains(url) else { continue }
            seen.insert(url)
            let title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : url
            tabs.append(OpenTab(url: url, title: title.isEmpty ? url : title))
        }
        return tabs
    }
}
