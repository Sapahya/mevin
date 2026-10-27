import AppKit
import CoreGraphics
import Foundation

/// Best-effort, read-only peeks at another app's on-disk state and window
/// title. Failures are silent. Nothing credential-shaped is returned.
enum AppStateReader {
    static func observe(bundleId: String) -> ObservedAppState? {
        let destination: ItemDestination?
        let note: String?
        switch bundleId {
        case Constants.claudeBundleID:
            destination = nil
            note = sanitizedTitle(bundleId: bundleId, skipping: ["Claude"])
        case Constants.figmaBundleID:
            destination = figmaDestination()
            note = destination == nil
                ? sanitizedTitle(bundleId: bundleId, skipping: ["Figma"])
                : nil
        case Constants.slackBundleID:
            destination = nil
            note = sanitizedTitle(bundleId: bundleId, skipping: ["Slack"])
        default:
            return nil
        }
        if destination == nil, note == nil { return nil }
        return ObservedAppState(bundleId: bundleId, destination: destination, note: note)
    }

    /// Figma's `desktop_state.json` sometimes lists open files with a `fileKey`.
    /// Only that exact field, and only when it matches the known key pattern,
    /// becomes a destination. Any other shape is ignored.
    private static func figmaDestination() -> ItemDestination? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Figma/desktop_state.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let key = firstFileKey(in: json), FigmaService.isValidFileKey(key) else {
            return nil
        }
        return .figma(kind: .design, fileKey: key, slug: nil, nodeId: nil)
    }

    private static func firstFileKey(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let key = dict["fileKey"] as? String, FigmaService.isValidFileKey(key) {
                return key
            }
            for child in dict.values {
                if let found = firstFileKey(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstFileKey(in: child) { return found }
            }
        }
        return nil
    }

    /// Window titles, when macOS still hands them out. Empty or just the app
    /// name is ignored. No Accessibility permission is requested.
    static func sanitizedTitle(bundleId: String, skipping names: [String]) -> String? {
        guard let raw = windowTitle(bundleId: bundleId) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if names.contains(where: { trimmed.caseInsensitiveCompare($0) == .orderedSame }) {
            return nil
        }
        return SessionCapture.sanitizedNote(trimmed)
    }

    private static func windowTitle(bundleId: String) -> String? {
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }
        guard let pid = running?.processIdentifier else { return nil }
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for window in info {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }
}
