import AppKit
import ApplicationServices
import Foundation

/// Window minimize, restore and close via Accessibility. Falls back silently when untrusted.
enum AccessibilityWindowControl {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func hasOnScreenNormalWindow(for pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return WindowClassifier.hasNormalWindow(for: pid, in: windows)
    }

    static func unminimizeWindows(for pid: pid_t) -> Bool {
        guard isTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let windowList = windows(of: app), !windowList.isEmpty else { return false }
        var changed = false
        for window in windowList {
            if setAttribute(window, kAXMinimizedAttribute, kCFBooleanFalse!) {
                changed = true
            }
        }
        return changed
    }

    static func minimizeWindows(for pid: pid_t) -> Bool {
        guard isTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let windowList = windows(of: app), !windowList.isEmpty else { return false }
        var changed = false
        for window in windowList {
            if setAttribute(window, kAXMinimizedAttribute, kCFBooleanTrue!) {
                changed = true
            }
        }
        return changed
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement]? {
        guard let raw = copyAttribute(app, kAXWindowsAttribute) else { return nil }
        return raw as? [AXUIElement]
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = copyAttribute(element, name) else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as AnyObject?
    }

    private static func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    private static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
