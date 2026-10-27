import AppKit
import Foundation

/// Opens a Claude page in Claude Desktop through `claude://`.
///
/// Verified 19 September 2026 against Claude 2.2553.1 (`claudeURLHandler`):
/// `OpenConversation` navigates to `/chat/<uuid>`, `OpenProject` to
/// `/project/<uuid>`, both gated on the same UUID pattern. Cowork opens
/// `/cowork/<uuid>` (the long `/cowork/project/<uuid>` shape still parses).
/// Code (`hu.Code`) extracts a session id from `/code/<id>` and accepts
/// `^(cse|session)_[A-Za-z0-9_-]+$`. A bare UUID is Cowork; a bare
/// `session_` / `cse_` id is Code. Mixing kinds still navigates, but to the
/// wrong page, so the kind from the pasted link is preserved and never
/// rewritten. Cowork is matched before a bare `project` segment, or a
/// Cowork paste would be stored as a project.
enum ClaudeService {
    static let bundleID = Constants.claudeBundleID
    static let webHost = "claude.ai"

    enum ParseError: Error, Equatable {
        case empty
        case wrongHost
        case noKind
        case newChat
        case noID
        case shareLink

        /// nil for empty input: the Add button stays disabled and no message shows.
        var message: String? {
            switch self {
            case .empty: return nil
            case .wrongHost: return "That isn't a Claude link."
            case .noKind: return "Paste a link, a Cowork UUID, or a session_ / cse_ id."
            case .newChat: return "That's a new chat, not a saved one. Open the conversation first, then copy its link."
            case .noID: return "That link doesn't have a valid id in it."
            case .shareLink:
                return "This is a share link. It opens a read-only copy, not your conversation. Paste the conversation's own link instead (it contains /chat/, /cowork/ or /code/)."
            }
        }
    }

    struct ParsedLink: Equatable {
        var kind: ClaudeLinkKind
        var id: String
    }

    /// Same check the desktop handler uses before navigating to a UUID item.
    /// Anything that fails this is sent to the list instead of the item.
    private static let itemIDPattern = try! NSRegularExpression(
        pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )

    /// Same check the desktop handler uses for Code session ids (`fhn` / `dhn`).
    /// `local_` ids are resume-only and are rejected here on purpose.
    private static let codeIDPattern = try! NSRegularExpression(
        pattern: "^(cse|session)_[A-Za-z0-9_-]+$"
    )

    static func isInstalled() -> Bool {
        LaunchService.applicationURL(bundleId: bundleID) != nil
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
    }

    /// Pure. No UI, no I/O. The v3 table plus the v5 Cowork and Code rows
    /// are the spec for this function.
    static func parse(_ raw: String) -> Result<ParsedLink, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        // Bare ids before a URL: a UUID is Cowork, session_/cse_ is Code.
        if isValidID(trimmed, kind: .cowork) {
            return .success(ParsedLink(kind: .cowork, id: normalizedID(trimmed, kind: .cowork)))
        }
        if isValidID(trimmed, kind: .code) {
            return .success(ParsedLink(kind: .code, id: normalizedID(trimmed, kind: .code)))
        }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme) else {
            return .failure(.wrongHost)
        }

        guard let host = normalizedHost(components.host) else {
            return .failure(.wrongHost)
        }
        guard host == webHost else { return .failure(.wrongHost) }

        let parts = (components.path)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if parts.contains("share") {
            return .failure(.shareLink)
        }

        if let parsed = parseCowork(parts) {
            return parsed
        }

        guard let kindIndex = parts.firstIndex(where: {
            $0 == "project" || $0 == "chat" || $0 == "code"
        }) else {
            return .failure(.noKind)
        }

        let kind: ClaudeLinkKind
        switch parts[kindIndex] {
        case "chat": kind = .chat
        case "code": kind = .code
        default: kind = .project
        }

        let nextIndex = parts.index(after: kindIndex)
        guard nextIndex < parts.endIndex else { return .failure(.noID) }

        let next = parts[nextIndex]
        if kind == .chat, next == "new" { return .failure(.newChat) }
        guard isValidID(next, kind: kind) else { return .failure(.noID) }

        return .success(ParsedLink(kind: kind, id: normalizedID(next, kind: kind)))
    }

    static func desktopURL(kind: ClaudeLinkKind, id: String) -> URL? {
        guard isValidID(id, kind: kind) else { return nil }
        let id = normalizedID(id, kind: kind)
        return URL(string: "claude://\(webHost)\(path(kind: kind, id: id))")
    }

    static func httpsURL(kind: ClaudeLinkKind, id: String) -> String {
        let id = isValidID(id, kind: kind) ? normalizedID(id, kind: kind) : id
        return "https://\(webHost)\(path(kind: kind, id: id))"
    }

    static func isValidID(_ raw: String, kind: ClaudeLinkKind) -> Bool {
        switch kind {
        case .chat, .project, .cowork:
            return isItemID(raw)
        case .code:
            let range = NSRange(raw.startIndex..., in: raw)
            return codeIDPattern.firstMatch(in: raw, options: [], range: range) != nil
        }
    }

    static func normalizedID(_ raw: String, kind: ClaudeLinkKind) -> String {
        switch kind {
        case .code: return raw
        case .chat, .project, .cowork: return raw.lowercased()
        }
    }

    static func isItemID(_ raw: String) -> Bool {
        let range = NSRange(raw.startIndex..., in: raw)
        return itemIDPattern.firstMatch(in: raw, options: [], range: range) != nil
    }

    /// Cowork is `/cowork/<uuid>`. The older `/cowork/project/<uuid>` shape
    /// still parses so stored long URLs keep working.
    /// Matched before the generic `project` scan so a Cowork paste cannot be
    /// stored as `.project`.
    private static func parseCowork(_ parts: [String]) -> Result<ParsedLink, ParseError>? {
        guard let coworkIndex = parts.firstIndex(of: "cowork") else { return nil }
        let idIndex: Int
        if coworkIndex + 1 < parts.count, parts[coworkIndex + 1] == "project" {
            idIndex = coworkIndex + 2
        } else {
            idIndex = coworkIndex + 1
        }
        guard idIndex < parts.endIndex else { return .failure(.noID) }
        let next = parts[idIndex]
        guard isValidID(next, kind: .cowork) else { return .failure(.noID) }
        return .success(ParsedLink(kind: .cowork, id: normalizedID(next, kind: .cowork)))
    }

    private static func path(kind: ClaudeLinkKind, id: String) -> String {
        switch kind {
        case .chat: return "/chat/\(id)"
        case .project: return "/project/\(id)"
        case .cowork: return "/cowork/\(id)"
        case .code: return "/code/\(id)"
        }
    }

    private static func normalizedHost(_ raw: String?) -> String? {
        guard var host = raw?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
