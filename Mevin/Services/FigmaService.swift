import AppKit
import Foundation

/// Opens a Figma file in the desktop app through `figma://`.
///
/// Verified 19 September 2026 against Figma 126.8.18. The app registers the
/// `figma` scheme (`com.figma.Desktop`). The open-url handler `$s` rewrites
/// `figma:` to `https://www.figma.com/` and opens a file tab from that path,
/// so a desktop URL is the https path with the scheme swapped. File keys match
/// `[0-9a-zA-Z]{22,128}` and are case-sensitive. The slug is optional. Both
/// `design` and `file` are accepted; the pasted kind is preserved.
enum FigmaService {
    static let bundleID = Constants.figmaBundleID
    static let webHost = "figma.com"

    enum ParseError: Error, Equatable {
        case empty
        case wrongHost
        case noKind
        case noKey

        /// nil for empty input: the Add button stays disabled and no message shows.
        var message: String? {
            switch self {
            case .empty: return nil
            case .wrongHost: return "That isn't a Figma link."
            case .noKind: return "Paste a link to a Figma file."
            case .noKey: return "That link doesn't have a Figma file in it."
            }
        }
    }

    struct ParsedLink: Equatable {
        var kind: FigmaFileKind
        var fileKey: String
        var slug: String?
        var nodeId: String?
    }

    /// Same bounds the desktop handler uses (`Ux` in app.asar).
    private static let fileKeyPattern = try! NSRegularExpression(
        pattern: "^[0-9a-zA-Z]{22,128}$"
    )

    static func isInstalled() -> Bool {
        LaunchService.applicationURL(bundleId: bundleID) != nil
            || FileManager.default.fileExists(atPath: "/Applications/Figma.app")
    }

    /// Pure. No UI, no I/O. Section 11 of the Figma PRD is the spec.
    static func parse(_ raw: String) -> Result<ParsedLink, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme) else {
            return .failure(.wrongHost)
        }

        guard let parts = pathParts(from: components) else {
            return .failure(.wrongHost)
        }
        guard let kindRaw = parts.first, let kind = FigmaFileKind(rawValue: kindRaw) else {
            return .failure(.noKind)
        }
        guard parts.count >= 2 else { return .failure(.noKey) }

        let fileKey = parts[1]
        guard isValidFileKey(fileKey) else { return .failure(.noKey) }

        let slug: String?
        if parts.count >= 3 {
            let third = parts[2]
            if third == "branch" { return .failure(.noKey) }
            slug = third.isEmpty ? nil : third
        } else {
            slug = nil
        }

        return .success(
            ParsedLink(
                kind: kind,
                fileKey: fileKey,
                slug: slug,
                nodeId: rawNodeID(from: components.percentEncodedQuery)
            )
        )
    }

    static func desktopURL(
        kind: FigmaFileKind,
        fileKey: String,
        slug: String?,
        nodeId: String?
    ) -> URL? {
        guard isValidFileKey(fileKey) else { return nil }
        return URL(string: "figma://" + resourcePath(kind: kind, fileKey: fileKey, slug: slug, nodeId: nodeId))
    }

    static func httpsURL(
        kind: FigmaFileKind,
        fileKey: String,
        slug: String?,
        nodeId: String?
    ) -> String {
        "https://www.\(webHost)/" + resourcePath(kind: kind, fileKey: fileKey, slug: slug, nodeId: nodeId)
    }

    static func isValidFileKey(_ raw: String) -> Bool {
        let range = NSRange(raw.startIndex..., in: raw)
        return fileKeyPattern.firstMatch(in: raw, options: [], range: range) != nil
    }

    /// Display only. The stored slug is untouched.
    static func displayName(slug: String?) -> String? {
        guard let slug, !slug.isEmpty else { return nil }
        let decoded = slug.removingPercentEncoding ?? slug
        return decoded.replacingOccurrences(of: "-", with: " ")
    }

    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// `figma://design/key` puts the kind in the host. `https://www.figma.com/design/key`
    /// puts it in the path. Both have to produce the same parts.
    private static func pathParts(from components: URLComponents) -> [String]? {
        guard let host = components.host, !host.isEmpty else { return nil }
        let path = encodedPathSegments(components.percentEncodedPath)
        let scheme = components.scheme?.lowercased()
        if normalizedHost(host) == webHost {
            return path
        }
        guard scheme == "figma" else { return nil }
        return [host] + path
    }

    private static func encodedPathSegments(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func rawNodeID(from query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == "node-id" else { continue }
            let value = String(pair[1])
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Assembled by concatenation so a stored `%3A` is not turned into `%253A`.
    private static func resourcePath(
        kind: FigmaFileKind,
        fileKey: String,
        slug: String?,
        nodeId: String?
    ) -> String {
        var path = "\(kind.rawValue)/\(fileKey)"
        if let slug, !slug.isEmpty {
            path += "/\(slug)"
        }
        if let nodeId, !nodeId.isEmpty {
            path += "?node-id=\(nodeId)"
        }
        return path
    }

    private static func normalizedHost(_ raw: String) -> String {
        var host = raw.lowercased()
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }
}
