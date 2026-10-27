import AppKit
import Foundation

/// Detects Chrome profile folder from chrome://version (PRD V5).
enum ChromeProfileDetectionService {
    struct DetectedProfile {
        var directoryName: String
        var rawPathFragment: String
        var suggestedName: String?
        /// Chrome's own name for the profile, read from the version page's
        /// window title before the tab closes.
        var chromeProfileName: String? = nil
    }

    enum Failure: Error {
        case chromeMissing
        case allMethodsFailed
        case waitingForClipboard

        var userMessage: String {
            switch self {
            case .chromeMissing:
                return "Google Chrome isn’t running. Open Chrome on the profile you want, then try again."
            case .allMethodsFailed:
                return "Copy the Profile Path line in Chrome. Mevin will fill it in when you copy."
            case .waitingForClipboard:
                return "Copy the Profile Path from chrome://version. Mevin is watching your clipboard."
            }
        }
    }

    /// Method 1 reads the page's text through Accessibility (verified on the
    /// owner's Mac, 27 Oct 2026). Method 3 (clipboard) is always available.
    static var accessibilityDetectionEnabled = true
    static var ocrDetectionEnabled = true

    @MainActor
    static func detect(panel: PanelController?) async -> Result<DetectedProfile, Failure> {
        guard ChromeService.isInstalled() else { return .failure(.chromeMissing) }

        if !ChromeService.openProfileInfo() {
            return .failure(.chromeMissing)
        }

        if accessibilityDetectionEnabled, AccessibilityWindowControl.isTrusted(),
           let reading = await readVersionPageWhenDrawn(),
           let directory = validatedDirectory(from: reading.path) {
            ChromeService.closeVersionPageTab()
            return .success(DetectedProfile(
                directoryName: directory,
                rawPathFragment: reading.path,
                suggestedName: nil,
                chromeProfileName: reading.profileName
            ))
        }

        if ocrDetectionEnabled, CGPreflightScreenCaptureAccess() {
            // The screenshot is read only once the page has loaded, and again
            // a few times in case Chrome hasn't drawn the table yet.
            await waitForVersionPageLoad()
            for attempt in 0 ..< ocrAttempts {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(500)) }
                guard let image = await ChromeProfileOCR.captureChromeWindowImage() else { continue }
                let lines = ChromeProfileOCR.recognizedLines(in: image)
                ChromeDebugLog.log("detect OCR attempt \(attempt + 1): \(lines.count) lines, path=\(ChromeProfileOCR.profilePath(from: lines) ?? "nil")")  // DEBUG-CHROME-LOG
                if let path = ChromeProfileOCR.profilePath(from: lines),
                   let directory = validatedDirectory(from: path) {
                    ChromeService.closeVersionPageTab()
                    return .success(DetectedProfile(
                        directoryName: directory,
                        rawPathFragment: path,
                        suggestedName: suggestedName(from: lines)
                    ))
                }
            }
        }

        let clipboard = await watchClipboard(seconds: 120, panel: panel)
        ChromeService.closeVersionPageTab()
        if let directory = clipboard {
            return .success(DetectedProfile(
                directoryName: directory.name,
                rawPathFragment: directory.raw,
                suggestedName: nil
            ))
        }
        return .failure(.allMethodsFailed)
    }

    static let ocrAttempts = 4

    /// Chrome builds the page's Accessibility text a moment after it loads,
    /// so the read is retried for up to about 4 seconds.
    @MainActor
    private static func readVersionPageWhenDrawn() async -> ChromeProfileAccessibilityReader.Reading? {
        for attempt in 0 ..< 16 {
            if let reading = ChromeProfileAccessibilityReader.readVersionPage() {
                ChromeDebugLog.log("detect AX: found path on attempt \(attempt + 1): \(reading.path) name=\(reading.profileName ?? "nil")")  // DEBUG-CHROME-LOG
                return reading
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        ChromeDebugLog.log("detect AX: no Profile Path text found after 16 attempts")  // DEBUG-CHROME-LOG
        return nil
    }

    /// Waits (up to about 5 seconds) until a chrome://version tab is showing
    /// and done loading, then a short moment for it to draw.
    @MainActor
    private static func waitForVersionPageLoad() async {
        for _ in 0 ..< 25 {
            if ChromeService.versionPageLoaded() { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func validatedDirectory(from raw: String) -> String? {
        guard let name = ChromeService.profileDirectoryName(fromPasted: raw),
              ChromeService.isLikelyProfileDirectory(name)
        else { return nil }
        return name
    }

    private static func suggestedName(from lines: [String]) -> String? {
        for line in lines {
            if line.localizedCaseInsensitiveContains("google chrome") && !line.contains("/") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private struct ClipboardHit {
        var name: String
        var raw: String
    }

    @MainActor
    private static func watchClipboard(seconds: TimeInterval, panel: PanelController?) async -> ClipboardHit? {
        let deadline = Date().addingTimeInterval(seconds)
        var lastChange = NSPasteboard.general.changeCount
        panel?.bringPanelToFront()
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(400))
            let board = NSPasteboard.general
            if board.changeCount == lastChange { continue }
            lastChange = board.changeCount
            guard let text = board.string(forType: .string) else { continue }
            guard text.contains("/Google/Chrome/") else { continue }
            if let name = validatedDirectory(from: text) {
                panel?.bringPanelToFront()
                return ClipboardHit(name: name, raw: text)
            }
        }
        return nil
    }
}
