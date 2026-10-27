import Foundation

/// One folder + optional command on the Terminal app row (PRD V5).
struct TerminalTab: Codable, Hashable, Identifiable {
    var id: UUID
    var path: String?
    var command: String?

    init(id: UUID = UUID(), path: String? = nil, command: String? = nil) {
        self.id = id
        self.path = path
        self.command = command
    }

    var trimmedCommand: String {
        command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct StoreFile: Codable {
    var version: Int
    var profiles: [Profile]
    var activeSession: ActiveSession?
    /// Apps Mevin must never close, regardless of role. See never-close list.
    var keepOpenBundleIds: [String]
    /// Newest first, at most three per profile. Beside the profile, never on it.
    var snapshots: [SessionSnapshot]
    /// CGWindow IDs Mevin associated with a role profile + Chrome directory (PRD V6).
    var chromeWindowBindings: [String: Int]
    /// Completed role sessions for stats (PRD V7).
    var roleUses: [RoleUseRecord]
    /// 2, 3, or 0 (off). Default 3.
    var checkInIntervalHours: Int

    init(
        version: Int,
        profiles: [Profile],
        activeSession: ActiveSession?,
        keepOpenBundleIds: [String] = [],
        snapshots: [SessionSnapshot] = [],
        chromeWindowBindings: [String: Int] = [:],
        roleUses: [RoleUseRecord] = [],
        checkInIntervalHours: Int = 3
    ) {
        self.version = version
        self.profiles = profiles
        self.activeSession = activeSession
        self.keepOpenBundleIds = keepOpenBundleIds
        self.snapshots = snapshots
        self.chromeWindowBindings = chromeWindowBindings
        self.roleUses = roleUses
        self.checkInIntervalHours = checkInIntervalHours
    }

    enum CodingKeys: String, CodingKey {
        case version, profiles, activeSession, keepOpenBundleIds, snapshots, chromeWindowBindings
        case roleUses, checkInIntervalHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A file written by hand may omit the version. Treat it as the oldest
        // shape so it goes through migration rather than being trusted as current.
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        activeSession = try c.decodeIfPresent(ActiveSession.self, forKey: .activeSession)
        keepOpenBundleIds = try c.decodeIfPresent([String].self, forKey: .keepOpenBundleIds) ?? []
        snapshots = try c.decodeIfPresent([SessionSnapshot].self, forKey: .snapshots) ?? []
        chromeWindowBindings = try c.decodeIfPresent([String: Int].self, forKey: .chromeWindowBindings) ?? [:]
        roleUses = try c.decodeIfPresent([RoleUseRecord].self, forKey: .roleUses) ?? []
        checkInIntervalHours = try c.decodeIfPresent(Int.self, forKey: .checkInIntervalHours) ?? 3
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(profiles, forKey: .profiles)
        try c.encodeIfPresent(activeSession, forKey: .activeSession)
        try c.encode(keepOpenBundleIds, forKey: .keepOpenBundleIds)
        try c.encode(snapshots, forKey: .snapshots)
        try c.encode(chromeWindowBindings, forKey: .chromeWindowBindings)
        try c.encode(roleUses, forKey: .roleUses)
        try c.encode(checkInIntervalHours, forKey: .checkInIntervalHours)
    }
}

/// The three draggable units of a profile. Links are not one of them: they are
/// passed to Chrome in the same launch command, so they always travel with it.
enum ItemGroup: String, Codable, CaseIterable, Hashable {
    case chromeWithLinks
    case apps
    case folders

    /// Chrome first because it is the slowest thing to start, so it can load
    /// while everything else opens.
    static let defaultOrder: [ItemGroup] = [.chromeWithLinks, .apps, .folders]

    var heading: String {
        switch self {
        case .chromeWithLinks: return "Chrome profile"
        case .apps: return "Apps"
        case .folders: return "Folders"
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var items: [ProfileItem]
    var groupOrder: [ItemGroup]
    /// One of the six palette ids. Never nil: a card has to have a colour.
    /// Empty here means "not yet assigned", which migration fills in.
    var colorId: String
    /// Detects edits to Terminal commands outside Mevin (PRD V6).
    var terminalCommandsFingerprint: String?
    /// Optional default session timer in minutes (PRD V7).
    var defaultTimerMinutes: Int?

    init(
        id: UUID = UUID(),
        name: String,
        items: [ProfileItem] = [],
        groupOrder: [ItemGroup] = ItemGroup.defaultOrder,
        colorId: String = ProfileColor.fallback.rawValue,
        terminalCommandsFingerprint: String? = nil,
        defaultTimerMinutes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.groupOrder = groupOrder
        self.colorId = colorId
        self.terminalCommandsFingerprint = terminalCommandsFingerprint
        self.defaultTimerMinutes = defaultTimerMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, items, groupOrder, colorId, terminalCommandsFingerprint, defaultTimerMinutes
    }

    // Hand-editing profiles.json is a supported way to use this app, so every
    // key except the name is allowed to be missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        items = try c.decodeIfPresent([ProfileItem].self, forKey: .items) ?? []
        let order = try c.decodeIfPresent([ItemGroup].self, forKey: .groupOrder) ?? []
        groupOrder = Profile.normalized(order)
        // Left empty rather than defaulted, so migration can tell a file that
        // predates colours from one that chose this colour deliberately.
        colorId = try c.decodeIfPresent(String.self, forKey: .colorId) ?? ""
        terminalCommandsFingerprint = try c.decodeIfPresent(String.self, forKey: .terminalCommandsFingerprint)
        defaultTimerMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultTimerMinutes)
    }

    func terminalTabsItem() -> ProfileItem? {
        items.first { $0.type == .app && $0.bundleId == Constants.terminalBundleID }
    }

    var color: ProfileColor {
        ProfileColor.named(colorId)
    }

    /// Keeps a hand-written or migrated order usable: no duplicates, no gaps.
    static func normalized(_ order: [ItemGroup]) -> [ItemGroup] {
        var result: [ItemGroup] = []
        for group in order where !result.contains(group) {
            result.append(group)
        }
        for group in ItemGroup.defaultOrder where !result.contains(group) {
            result.append(group)
        }
        return result
    }

    func items(in group: ItemGroup) -> [ProfileItem] {
        switch group {
        case .chromeWithLinks:
            return items.filter { $0.type == .chromeProfile }
        case .apps:
            return items.filter { $0.type == .app }
        case .folders:
            return items.filter { $0.type == .folder }
        }
    }

    var links: [ProfileItem] {
        items.filter { $0.type == .link }
    }

    var chromeProfile: ProfileItem? {
        items.first { $0.type == .chromeProfile }
    }

    var includesChrome: Bool {
        chromeProfile != nil
    }

    var chromeIsLinked: Bool {
        chromeProfile?.isChromeLinked ?? false
    }

    /// Apps to show and to verify after role start, in list order.
    func roleSurfaceBundleIdsInOrder() -> [String] {
        var ids: [String] = []
        for group in groupOrder {
            switch group {
            case .chromeWithLinks:
                if includesChrome {
                    ids.append(ChromeService.chromeBundleID)
                }
            case .apps:
                for item in items(in: .apps) {
                    if let bundleId = item.bundleId {
                        ids.append(bundleId)
                    }
                }
            case .folders:
                for item in items(in: .folders) {
                    if let opener = item.appBundleId, opener != Constants.finderBundleID {
                        ids.append(opener)
                    }
                }
            }
        }
        return ids
    }

    /// Destinations that ride with Chrome, only when that destination's desktop
    /// app is missing. Claude being installed must not hide a Figma fallback.
    var browserDestinationURLs: [String] {
        items.compactMap { item in
            guard let destination = item.destination else { return nil }
            return destination.isDesktopInstalled ? nil : destination.httpsURL
        }
    }

    var hasNameWorthKeeping: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ActiveSession: Codable, Hashable {
    var profileId: UUID
    var startedAt: Date
    /// Apps the user already had open when the session began. They are never
    /// asked to quit at the end, because the session did not open them.
    var baselineBundleIds: [String]
    /// Frontmost seconds accumulated so far. Written on the capture timer so a
    /// crash does not wipe the log.
    var focusSeconds: [String: Int]
    /// Apps kept on switch; excluded from new role control and snapshots (PRD V6).
    var carriedOverBundleIds: [String]
    /// Last keyboard or mouse activity seen during the session, and the awake
    /// seconds counted up to it. Written with each save so a session cut short
    /// by a crash or shutdown can still be recorded up to that point (PRD V7 Change 4).
    var lastActiveAt: Date?
    var countedSecondsAtLastActive: Int?

    init(
        profileId: UUID,
        startedAt: Date,
        baselineBundleIds: [String],
        focusSeconds: [String: Int] = [:],
        carriedOverBundleIds: [String] = [],
        lastActiveAt: Date? = nil,
        countedSecondsAtLastActive: Int? = nil
    ) {
        self.profileId = profileId
        self.startedAt = startedAt
        self.baselineBundleIds = baselineBundleIds
        self.focusSeconds = focusSeconds
        self.carriedOverBundleIds = carriedOverBundleIds
        self.lastActiveAt = lastActiveAt
        self.countedSecondsAtLastActive = countedSecondsAtLastActive
    }

    enum CodingKeys: String, CodingKey {
        case profileId, startedAt, baselineBundleIds, focusSeconds, carriedOverBundleIds
        case lastActiveAt, countedSecondsAtLastActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        baselineBundleIds = try c.decodeIfPresent([String].self, forKey: .baselineBundleIds) ?? []
        focusSeconds = try c.decodeIfPresent([String: Int].self, forKey: .focusSeconds) ?? [:]
        carriedOverBundleIds = try c.decodeIfPresent([String].self, forKey: .carriedOverBundleIds) ?? []
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        countedSecondsAtLastActive = try c.decodeIfPresent(Int.self, forKey: .countedSecondsAtLastActive)
    }
}

/// The last few notes of "where you actually were". Never written onto a profile.
struct SessionSnapshot: Codable, Hashable {
    var profileId: UUID
    var capturedAt: Date
    var focusSeconds: [String: Int]
    var observed: [ObservedAppState]
    var chromeTabHosts: [String]

    init(
        profileId: UUID,
        capturedAt: Date = Date(),
        focusSeconds: [String: Int] = [:],
        observed: [ObservedAppState] = [],
        chromeTabHosts: [String] = []
    ) {
        self.profileId = profileId
        self.capturedAt = capturedAt
        self.focusSeconds = focusSeconds
        self.observed = observed
        self.chromeTabHosts = chromeTabHosts
    }

    enum CodingKeys: String, CodingKey {
        case profileId, capturedAt, focusSeconds, observed, chromeTabHosts, chromeTabURLs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        focusSeconds = try c.decodeIfPresent([String: Int].self, forKey: .focusSeconds) ?? [:]
        observed = try c.decodeIfPresent([ObservedAppState].self, forKey: .observed) ?? []
        if let hosts = try c.decodeIfPresent([String].self, forKey: .chromeTabHosts) {
            chromeTabHosts = hosts
        } else {
            let urls = try c.decodeIfPresent([String].self, forKey: .chromeTabURLs) ?? []
            chromeTabHosts = urls.compactMap { ProfileItem.host(of: $0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profileId, forKey: .profileId)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(focusSeconds, forKey: .focusSeconds)
        try c.encode(observed, forKey: .observed)
        try c.encode(chromeTabHosts, forKey: .chromeTabHosts)
    }
}

struct ObservedAppState: Codable, Hashable {
    var bundleId: String
    var destination: ItemDestination?
    var note: String?
}

enum ClaudeLinkKind: String, Codable, Hashable {
    case project
    case chat
    case cowork
    case code
}

enum FigmaFileKind: String, Codable, Hashable {
    case design
    case file
    case board
    case slides
    case proto
    case deck
}

/// Where an app should land. Claude was first; Figma is the second case;
/// Slack is the third.
enum ItemDestination: Codable, Hashable {
    case claude(kind: ClaudeLinkKind, id: String)
    case figma(kind: FigmaFileKind, fileKey: String, slug: String?, nodeId: String?)
    case slack(team: String, channel: String?)

    var httpsURL: String {
        switch self {
        case .claude(let kind, let id):
            return ClaudeService.httpsURL(kind: kind, id: id)
        case .figma(let kind, let fileKey, let slug, let nodeId):
            return FigmaService.httpsURL(kind: kind, fileKey: fileKey, slug: slug, nodeId: nodeId)
        case .slack(let team, let channel):
            return SlackService.httpsURL(team: team, channel: channel)
        }
    }

    var desktopURL: URL? {
        switch self {
        case .claude(let kind, let id):
            return ClaudeService.desktopURL(kind: kind, id: id)
        case .figma(let kind, let fileKey, let slug, let nodeId):
            return FigmaService.desktopURL(kind: kind, fileKey: fileKey, slug: slug, nodeId: nodeId)
        case .slack(let team, let channel):
            return SlackService.desktopURL(team: team, channel: channel)
        }
    }

    var isDesktopInstalled: Bool {
        switch self {
        case .claude: return ClaudeService.isInstalled()
        case .figma: return FigmaService.isInstalled()
        case .slack: return SlackService.isInstalled()
        }
    }

    /// Shown on the row. File keys, node ids and UUIDs are never included.
    var summary: String {
        let base: String
        switch self {
        case .claude(let kind, _):
            switch kind {
            case .project: base = "Opens a project"
            case .chat: base = "Opens a conversation"
            case .cowork: base = "Opens a Cowork session"
            case .code: base = "Opens a Claude Code session"
            }
        case .figma(_, _, let slug, let nodeId):
            if let name = FigmaService.displayName(slug: slug) {
                base = nodeId == nil ? "Opens \(name)" : "Opens a page in \(name)"
            } else {
                base = "Opens a Figma file"
            }
        case .slack(_, let channel):
            base = channel == nil ? "Opens a Slack workspace" : "Opens a Slack channel"
        }
        return isDesktopInstalled ? base : "\(base) · in your browser"
    }

    enum CodingKeys: String, CodingKey {
        case claude, figma, slack, webProject, desktopProject
    }

    private struct ClaudePayload: Codable {
        var kind: ClaudeLinkKind?
        var id: String?
        /// v5 stored these names before kind/id.
        var claudeKind: ClaudeLinkKind?
        var claudeID: String?

        enum PayloadKeys: String, CodingKey {
            case kind, id, claudeKind, claudeID
        }

        init(kind: ClaudeLinkKind? = nil, id: String? = nil, claudeKind: ClaudeLinkKind? = nil, claudeID: String? = nil) {
            self.kind = kind
            self.id = id
            self.claudeKind = claudeKind
            self.claudeID = claudeID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: PayloadKeys.self)
            kind = try c.decodeIfPresent(ClaudeLinkKind.self, forKey: .kind)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            claudeKind = try c.decodeIfPresent(ClaudeLinkKind.self, forKey: .claudeKind)
            claudeID = try c.decodeIfPresent(String.self, forKey: .claudeID)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: PayloadKeys.self)
            try c.encodeIfPresent(kind, forKey: .kind)
            try c.encodeIfPresent(id, forKey: .id)
        }
    }

    private struct URLPayload: Codable { var url: String }

    private struct FigmaPayload: Codable {
        var kind: FigmaFileKind
        var fileKey: String
        var slug: String?
        var nodeId: String?
    }

    private struct SlackPayload: Codable {
        var team: String
        var channel: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try c.decodeIfPresent(ClaudePayload.self, forKey: .claude),
           let parsed = Self.link(from: payload) {
            self = .claude(kind: parsed.kind, id: parsed.id)
            return
        }
        if let payload = try c.decodeIfPresent(URLPayload.self, forKey: .webProject),
           case .success(let parsed) = ClaudeService.parse(payload.url) {
            self = .claude(kind: parsed.kind, id: parsed.id)
            return
        }
        if let payload = try c.decodeIfPresent(URLPayload.self, forKey: .desktopProject),
           case .success(let parsed) = ClaudeService.parse(payload.url) {
            self = .claude(kind: parsed.kind, id: parsed.id)
            return
        }
        if let payload = try c.decodeIfPresent(FigmaPayload.self, forKey: .figma),
           FigmaService.isValidFileKey(payload.fileKey) {
            let slug = payload.slug.flatMap { $0.isEmpty ? nil : $0 }
            let nodeId = payload.nodeId.flatMap { $0.isEmpty ? nil : $0 }
            self = .figma(kind: payload.kind, fileKey: payload.fileKey, slug: slug, nodeId: nodeId)
            return
        }
        if let payload = try c.decodeIfPresent(SlackPayload.self, forKey: .slack),
           SlackService.isValidTeam(payload.team) {
            let channel = payload.channel.flatMap { SlackService.isValidChannel($0) ? $0 : nil }
            self = .slack(team: payload.team, channel: channel)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown destination")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claude(let kind, let id):
            try c.encode(ClaudePayload(kind: kind, id: id), forKey: .claude)
        case .figma(let kind, let fileKey, let slug, let nodeId):
            try c.encode(
                FigmaPayload(kind: kind, fileKey: fileKey, slug: slug, nodeId: nodeId),
                forKey: .figma
            )
        case .slack(let team, let channel):
            try c.encode(SlackPayload(team: team, channel: channel), forKey: .slack)
        }
    }

    private static func link(from payload: ClaudePayload) -> ClaudeService.ParsedLink? {
        if let kind = payload.kind, let id = payload.id, ClaudeService.isValidID(id, kind: kind) {
            return .init(kind: kind, id: ClaudeService.normalizedID(id, kind: kind))
        }
        if let id = payload.claudeID, ClaudeService.isItemID(id) {
            return .init(kind: payload.claudeKind ?? .project, id: id.lowercased())
        }
        return nil
    }
}

struct ProfileItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case app
        case chromeProfile
        case link
        case folder

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            // v1 spellings, kept so an existing profiles.json still loads.
            case "chromeAccount", "chromeProfile": self = .chromeProfile
            case "url", "link": self = .link
            case "app": self = .app
            case "folder": self = .folder
            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unknown item type \(raw)")
                )
            }
        }
    }

    var id: UUID
    var type: Kind
    var bundleId: String?
    var name: String?
    var directory: String?
    var displayName: String?
    var url: String?
    var title: String?
    var path: String?
    /// nil means the folder opens in Finder.
    var appBundleId: String?
    var appName: String?
    /// Legacy v7: migrated to Terminal app `terminalTabs`. Decoded only.
    var startupCommand: String?
    /// Terminal app row only: tabs run when the role starts.
    var terminalTabs: [TerminalTab]?
    /// Apps only. Where to send the app once it is open.
    var destination: ItemDestination?
    /// Toolbar profile label from detect (PRD V6 Chrome window reuse).
    var chromeToolbarName: String?

    init(
        id: UUID = UUID(),
        type: Kind,
        bundleId: String? = nil,
        name: String? = nil,
        directory: String? = nil,
        displayName: String? = nil,
        url: String? = nil,
        title: String? = nil,
        path: String? = nil,
        appBundleId: String? = nil,
        appName: String? = nil,
        startupCommand: String? = nil,
        terminalTabs: [TerminalTab]? = nil,
        destination: ItemDestination? = nil,
        chromeToolbarName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.bundleId = bundleId
        self.name = name
        self.directory = directory
        self.displayName = displayName
        self.url = url
        self.title = title
        self.path = path
        self.appBundleId = appBundleId
        self.appName = appName
        self.startupCommand = startupCommand
        self.terminalTabs = terminalTabs
        self.destination = destination
        self.chromeToolbarName = chromeToolbarName
    }

    static func app(bundleId: String, name: String, terminalTabs: [TerminalTab]? = nil) -> ProfileItem {
        ProfileItem(type: .app, bundleId: bundleId, name: name, terminalTabs: terminalTabs)
    }

    static func effectiveTerminalPath(for tab: TerminalTab) -> String {
        tab.path ?? NSHomeDirectory()
    }

    /// Collapsed Terminal row when tabs are configured.
    var terminalRowSummary: String? {
        guard type == .app, bundleId == Constants.terminalBundleID else { return nil }
        guard let tabs = terminalTabs, !tabs.isEmpty else { return nil }
        let segments = tabs.map { tab -> String in
            let folderLabel: String
            if let path = tab.path, !path.isEmpty {
                folderLabel = (path as NSString).lastPathComponent
            } else {
                folderLabel = "~"
            }
            let cmd = tab.trimmedCommand
            return cmd.isEmpty ? folderLabel : "\(folderLabel): \(cmd)"
        }
        let count = tabs.count == 1 ? "1 tab" : "\(tabs.count) tabs"
        return "Terminal · \(count) · \(segments.joined(separator: " · "))"
    }

    static func chromeProfile(directory: String, displayName: String) -> ProfileItem {
        ProfileItem(type: .chromeProfile, directory: directory, displayName: displayName)
    }

    static func unlinkedChrome() -> ProfileItem {
        ProfileItem(type: .chromeProfile, displayName: "Google Chrome")
    }

    var isChromeLinked: Bool {
        guard type == .chromeProfile else { return false }
        guard let directory, !directory.isEmpty else { return false }
        return true
    }

    static func link(url: String, title: String) -> ProfileItem {
        ProfileItem(type: .link, url: url, title: title)
    }

    static func folder(
        path: String,
        appBundleId: String? = nil,
        appName: String? = nil,
        startupCommand: String? = nil
    ) -> ProfileItem {
        ProfileItem(
            type: .folder,
            path: path,
            appBundleId: appBundleId,
            appName: appName,
            startupCommand: startupCommand
        )
    }

    var label: String {
        switch type {
        case .app:
            return name ?? bundleId ?? "App"
        case .chromeProfile:
            return displayName ?? directory ?? "Chrome"
        case .link:
            if let title, !title.isEmpty { return title }
            return url.flatMap { ProfileItem.host(of: $0) } ?? url ?? "Link"
        case .folder:
            guard let path, !path.isEmpty else { return "Folder" }
            return (path as NSString).lastPathComponent
        }
    }

    /// A subtitle exists only where the item opens somewhere specific. That
    /// absence is how a bare app reads differently from a folder or a link.
    var subtitle: String? {
        switch type {
        case .app:
            // An app says nothing unless it is going somewhere specific.
            return destination?.summary
        case .chromeProfile:
            return nil
        case .link:
            guard let url else { return nil }
            return ProfileItem.host(of: url) ?? url
        case .folder:
            guard let path else { return nil }
            return (path as NSString).abbreviatingWithTildeInPath
        }
    }

    var opensInLabel: String {
        "Opens in \(appName ?? "Finder")"
    }

    /// Bundle IDs a session is responsible for quitting. Links ride inside
    /// Chrome, and Finder is the system, so neither is ever asked to quit.
    var closeBundleId: String? {
        switch type {
        case .app:
            return bundleId
        case .chromeProfile:
            return ChromeService.chromeBundleID
        case .link:
            return nil
        case .folder:
            guard let appBundleId, appBundleId != Constants.finderBundleID else { return nil }
            return appBundleId
        }
    }

    static func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// A user pasting `linkedin.com/in/me` means a web address, so add the
    /// scheme rather than rejecting the input.
    static func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://" + trimmed
        }

        guard let parsed = URL(string: candidate),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host,
              host.contains(".")
        else { return nil }

        return candidate
    }

    enum CodingKeys: String, CodingKey {
        case id, type, bundleId, name, directory, displayName, url, title, path, appBundleId, appName
        case startupCommand
        case terminalTabs
        case destination
        case chromeToolbarName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(Kind.self, forKey: .type)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        directory = try c.decodeIfPresent(String.self, forKey: .directory)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        appBundleId = try c.decodeIfPresent(String.self, forKey: .appBundleId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        startupCommand = try c.decodeIfPresent(String.self, forKey: .startupCommand)
        terminalTabs = try c.decodeIfPresent([TerminalTab].self, forKey: .terminalTabs)
        chromeToolbarName = try c.decodeIfPresent(String.self, forKey: .chromeToolbarName)
        do {
            destination = try c.decodeIfPresent(ItemDestination.self, forKey: .destination)
        } catch {
            destination = nil
        }

        // v1 wrote the editor name into `name` as well, which now renders as
        // the row title. The folder name is derived from the path instead.
        if type == .folder {
            name = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type.rawValue, forKey: .type)
        try c.encodeIfPresent(bundleId, forKey: .bundleId)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(directory, forKey: .directory)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(appBundleId, forKey: .appBundleId)
        try c.encodeIfPresent(appName, forKey: .appName)
        if type == .folder {
            try c.encodeIfPresent(startupCommand, forKey: .startupCommand)
        }
        if type == .app, bundleId == Constants.terminalBundleID {
            try c.encodeIfPresent(terminalTabs, forKey: .terminalTabs)
        }
        try c.encodeIfPresent(destination, forKey: .destination)
        if type == .chromeProfile {
            try c.encodeIfPresent(chromeToolbarName, forKey: .chromeToolbarName)
        }
    }
}

enum Screen: Equatable {
    case list
    case newProfile
    case builder
    case keepOpen
    case aiSettings
    case settings
    case proposal
    case keepOpenConfirm
    case quitConfirm
}

enum KeepOpenConfirmMode: Equatable {
    case starting(profileId: UUID)
    case switching(toProfileId: UUID)
    case ending
}

struct AutoEndBanner: Equatable {
    var profileId: UUID
    var profileName: String
    var lastActivityAt: Date
}

/// What a run could not open, kept item by item so each one can be removed
/// from the profile at the moment it fails.
///
/// Each failure is one full line ("Couldn't bring up: Music", "Couldn't run:
/// npm run dev (folder missing)", or a Chrome note), so different kinds of
/// problem never get joined into one sentence.
struct StartReport: Equatable {
    struct Failure: Equatable, Identifiable {
        /// The profile item it came from; Remove deletes that item.
        var id: UUID
        var label: String
        /// False for notes about an item that still opened (Chrome reuse) and
        /// for one tab of the Terminal row, where removing the row would lose
        /// every other tab.
        var removable: Bool = true
    }

    var profileId: UUID
    var failures: [Failure]

    static func bringUpLabel(_ name: String) -> String {
        "Couldn't bring up: \(name)"
    }
}

enum Constants {
    static let bundleID = "com.toshit.mevin"
    static let finderBundleID = "com.apple.finder"
    static let terminalBundleID = "com.apple.Terminal"
    static let musicBundleID = "com.apple.Music"
    static let ignoredBundleIDs: Set<String> = [
        bundleID,
        finderBundleID,
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager"
    ]
    static let chromeBundleIDs: Set<String> = [
        ChromeService.chromeBundleID,
        "com.google.Chrome.canary",
        "com.google.Chrome.beta"
    ]
    /// Offered as "Opens in" choices for folders, in this order.
    static let editorBundleIDs = [
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.sublimetext.4"
    ]
    /// Apps that can be sent to a specific destination. Only apps with a tested
    /// route belong here.
    static let claudeBundleID = "com.anthropic.claudefordesktop"
    static let figmaBundleID = "com.figma.Desktop"
    static let slackBundleID = "com.tinyspeck.slackmacgap"
}
