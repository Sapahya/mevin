import AppKit
import Foundation

/// Opens a Slack workspace or channel in Slack Desktop through `slack://`.
///
/// Slack.app registers the `slack` scheme (`com.tinyspeck.slackmacgap`). The
/// shapes below are the ones Slack documents and the desktop app accepts:
/// `slack://open?team=`, `slack://channel?team=&id=`, and the web equivalent
/// `https://app.slack.com/client/<team>/<channel>`.
enum SlackService {
    static let bundleID = Constants.slackBundleID
    static let webHost = "app.slack.com"

    enum ParseError: Error, Equatable {
        case empty
        case wrongHost
        case noTeam

        var message: String? {
            switch self {
            case .empty: return nil
            case .wrongHost: return "That isn't a Slack link."
            case .noTeam: return "That link doesn't have a Slack workspace in it."
            }
        }
    }

    struct ParsedLink: Equatable {
        var team: String
        var channel: String?
    }

    /// Workspace ids are `T…`. Channels are `C…`, DMs `D…`, groups `G…`.
    private static let teamPattern = try! NSRegularExpression(pattern: "^T[A-Z0-9]+$")
    private static let channelPattern = try! NSRegularExpression(pattern: "^[CDG][A-Z0-9]+$")

    static func isInstalled() -> Bool {
        LaunchService.applicationURL(bundleId: bundleID) != nil
            || FileManager.default.fileExists(atPath: "/Applications/Slack.app")
    }

    static func parse(_ raw: String) -> Result<ParsedLink, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme) else {
            return .failure(.wrongHost)
        }

        let scheme = components.scheme?.lowercased() ?? ""
        if scheme == "slack" {
            return parseSlackScheme(components)
        }

        guard let host = normalizedHost(components.host) else {
            return .failure(.wrongHost)
        }

        if host == webHost {
            return parseClientPath(components)
        }
        if host.hasSuffix(".slack.com"), host != "app.slack.com" {
            return parseWorkspaceHost(components)
        }
        return .failure(.wrongHost)
    }

    static func desktopURL(team: String, channel: String?) -> URL? {
        guard isValidTeam(team) else { return nil }
        if let channel, isValidChannel(channel) {
            return URL(string: "slack://channel?team=\(team)&id=\(channel)")
        }
        return URL(string: "slack://open?team=\(team)")
    }

    static func httpsURL(team: String, channel: String?) -> String {
        if let channel, isValidChannel(channel) {
            return "https://\(webHost)/client/\(team)/\(channel)"
        }
        return "https://\(webHost)/client/\(team)"
    }

    static func isValidTeam(_ raw: String) -> Bool {
        matches(teamPattern, raw)
    }

    static func isValidChannel(_ raw: String) -> Bool {
        matches(channelPattern, raw)
    }

    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    private static func parseSlackScheme(_ components: URLComponents) -> Result<ParsedLink, ParseError> {
        let items = components.queryItems ?? []
        let team = items.first(where: { $0.name == "team" })?.value
        let channel = items.first(where: { $0.name == "id" })?.value
        guard let team, isValidTeam(team) else { return .failure(.noTeam) }
        if let channel, isValidChannel(channel) {
            return .success(ParsedLink(team: team, channel: channel))
        }
        return .success(ParsedLink(team: team, channel: nil))
    }

    private static func parseClientPath(_ components: URLComponents) -> Result<ParsedLink, ParseError> {
        let parts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.first == "client", parts.count >= 2 else { return .failure(.noTeam) }
        let team = parts[1]
        guard isValidTeam(team) else { return .failure(.noTeam) }
        let channel = parts.count >= 3 && isValidChannel(parts[2]) ? parts[2] : nil
        return .success(ParsedLink(team: team, channel: channel))
    }

    /// `https://acme.slack.com/archives/C123` — the host is a name, not a team id,
    /// so this is only accepted when the path already carries a channel id. The
    /// workspace still has to come from a `team` query or we refuse rather than
    /// invent a T-id from the subdomain.
    private static func parseWorkspaceHost(_ components: URLComponents) -> Result<ParsedLink, ParseError> {
        let items = components.queryItems ?? []
        if let team = items.first(where: { $0.name == "team" })?.value, isValidTeam(team) {
            let parts = components.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            let channel = parts.count >= 2 && parts[0] == "archives" && isValidChannel(parts[1])
                ? parts[1] : nil
            return .success(ParsedLink(team: team, channel: channel))
        }
        return .failure(.noTeam)
    }

    private static func normalizedHost(_ raw: String?) -> String? {
        guard var host = raw?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    private static func matches(_ regex: NSRegularExpression, _ raw: String) -> Bool {
        let range = NSRange(raw.startIndex..., in: raw)
        return regex.firstMatch(in: raw, options: [], range: range) != nil
    }
}
