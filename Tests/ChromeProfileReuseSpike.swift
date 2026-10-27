import AppKit
import Foundation

/// Run with `make spike-chrome-reuse` while Chrome is running. Read-only: lists
/// Chrome's windows and the profile name read from each window's toolbar.
@main
struct ChromeProfileReuseSpike {
    static func main() {
        print("Chrome profile window reuse spike (PRD V6–V7)")
        guard ChromeService.isInstalled() else {
            print("skip reason=chrome_not_installed")
            return
        }
        let windows = ChromeWindowService.windows()
        print("windows=\(windows.count)")
        let names = ChromeWindowService.profileNames(for: windows)
        for window in windows {
            print("id=\(window.id) minimized=\(window.minimized) profile=\(names[window.id] ?? "unreadable") title=\(window.name)")
        }
    }
}
