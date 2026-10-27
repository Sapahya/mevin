import AppKit
import Foundation

/// Run with `make spike-chrome-detect` while Chrome is open on a profile.
@main
struct ChromeProfileDetectSpike {
    static func main() async {
        print("Chrome profile detection spike (PRD V5)")
        guard ChromeService.isInstalled() else {
            print("method1=skip reason=chrome_not_installed")
            print("method2=skip reason=chrome_not_installed")
            return
        }
        if !ChromeService.openProfileInfo() {
            print("method1=fail reason=could_not_open_version")
            print("method2=fail reason=could_not_open_version")
            return
        }
        var reading: ChromeProfileAccessibilityReader.Reading?
        for attempt in 1 ... 16 {
            reading = ChromeProfileAccessibilityReader.readVersionPage()
            if reading != nil { print("method1 read on attempt \(attempt)"); break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if let reading,
           let name = ChromeService.profileDirectoryName(fromPasted: reading.path),
           ChromeService.isLikelyProfileDirectory(name) {
            print("method1=pass profile=\(name) chromeName=\(reading.profileName ?? "nil")")
        } else {
            print("method1=fail")
        }
        print("versionPageLoaded=\(ChromeService.versionPageLoaded())")

        if CGPreflightScreenCaptureAccess() {
            if let image = await ChromeProfileOCR.captureChromeWindowImage() {
                let lines = ChromeProfileOCR.recognizedLines(in: image)
                if let path = ChromeProfileOCR.profilePath(from: lines),
                   let name = ChromeService.profileDirectoryName(fromPasted: path),
                   ChromeService.isLikelyProfileDirectory(name) {
                    print("method2=pass profile=\(name) lines=\(lines.count)")
                } else {
                    print("method2=fail lines=\(lines.count)")
                }
            } else {
                print("method2=fail reason=no_window_image")
            }
        } else {
            print("method2=skip reason=screen_recording_not_granted")
        }

        ChromeService.closeVersionPageTab()
    }
}
