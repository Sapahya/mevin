import AppKit
import Foundation
import ScreenCaptureKit
import Vision

/// On-device text recognition for Chrome profile detection (PRD V5). No network.
enum ChromeProfileOCR {
    static func recognizedLines(in image: CGImage) -> [String] {
        var lines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                if let candidate = observation.topCandidates(1).first?.string {
                    lines.append(candidate)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return lines
    }

    static func profilePath(from lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains("profile path") {
                let tail = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { return tail }
                if index + 1 < lines.count {
                    let next = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !next.isEmpty { return next }
                }
            }
        }
        for line in lines {
            if line.contains("/Google/Chrome/") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Captures Chrome's front window into memory with ScreenCaptureKit
    /// (macOS 14+). Nothing is written to disk and the image is dropped as soon
    /// as the text has been read (PRD V6 5.5). Needs Screen Recording.
    static func captureChromeWindowImage() async -> CGImage? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == ChromeService.chromeBundleID
        }) else { return nil }
        let pid = app.processIdentifier
        // CoreGraphics lists on-screen windows front to back, so the first
        // large Chrome window here is the one showing chrome://version.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = windows.first(where: { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int32, owner == pid else { return false }
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Width", default: 0] ?? 0) > 200
        }),
        let windowID = window[kCGWindowNumber as String] as? CGWindowID
        else { return nil }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let target = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int(target.frame.width * scale))
        configuration.height = max(1, Int(target.frame.height * scale))
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
