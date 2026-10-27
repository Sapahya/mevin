import AppKit
import ApplicationServices
import Foundation

/// Reads chrome://version through Accessibility (PRD V5 method 1). Chrome
/// shows the page as a table, so "Profile Path", ":" and the path itself are
/// separate text elements, read in on-screen order.
enum ChromeProfileAccessibilityReader {
    struct Reading: Equatable {
        var path: String
        /// Chrome's name for the profile, from the window title.
        var profileName: String?
    }

    /// The Profile Path from an open chrome://version window, or nil when the
    /// page hasn't drawn yet or Accessibility is off.
    static func readVersionPage() -> Reading? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == ChromeService.chromeBundleID
        }) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        for window in windows {
            var texts: [String] = []
            collectTexts(in: window, into: &texts)
            if let path = profilePath(fromTexts: texts) {
                let title = string(window, kAXTitleAttribute) ?? ""
                return Reading(path: path, profileName: ChromeWindowService.profileName(fromWindowTitle: title))
            }
        }
        return nil
    }

    /// The path that follows the "Profile Path" label; any Chrome profile
    /// folder path on the page if the label isn't found.
    static func profilePath(fromTexts texts: [String]) -> String? {
        func isProfileFolderPath(_ text: String) -> Bool {
            text.contains("/Application Support/Google/Chrome/")
        }
        if let label = texts.firstIndex(where: { $0.localizedCaseInsensitiveContains("profile path") }) {
            if let inline = ChromeService.extractProfilePathLine(from: texts[label]), isProfileFolderPath(inline) {
                return inline
            }
            if let next = texts[(label + 1)...].prefix(3).first(where: isProfileFolderPath) {
                return next.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return texts.first(where: isProfileFolderPath)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collectTexts(in element: AXUIElement, into texts: inout [String], depth: Int = 0) {
        guard depth < 60, texts.count < 2000 else { return }
        let role = string(element, kAXRoleAttribute) ?? ""
        if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
            if let value = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute), !value.isEmpty {
                texts.append(value)
            }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }
        for child in children {
            collectTexts(in: child, into: &texts, depth: depth + 1)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
