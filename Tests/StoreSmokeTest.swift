// Exercises the on-disk format and the pure model rules without launching the
// app, so a schema or migration mistake shows up before it eats a real
// profiles.json. Run with `make smoke`.
import CoreGraphics
import Foundation

@main
struct StoreSmokeTest {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        if condition {
            print("ok   \(label)")
        } else {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maal-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try roundTrip(in: tempDir)
        try migration(in: tempDir)
        try migrationFromV2(in: tempDir)
        try migrationFromV3(in: tempDir)
        try migrationFromV4(in: tempDir)
        try migrationFromV5(in: tempDir)
        try migrationFromV7(in: tempDir)
        links()
        rowCopy()
        closeTargets()
        groupOrder()
        colours()
        destinations()
        figmaDestinations()
        keepOpen()
        chromeEntry()
        chromeDiagnostic()
        aiProvider()
        appMatcher()
        switchPlan()
        roleTeardown()
        terminalStartup()
        chromeProfileDetection()
        slackDestinations()
        sessionSnapshots()
        windowClassifier()
        chromeLinkValidation()
        v6Helpers()
        v7Stats()
        chromeToolbarSeedClear()
        phase1Fixes()
        v10SwitchPanel()
        v11()
        chromeDetectAndTitles()
        v9ChromeProfile()

        if failures == 0 {
            print("\nall checks passed")
        } else {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
    }

    // MARK: - Storage

    static func roundTrip(in dir: URL) throws {
        let fileURL = dir.appendingPathComponent("profiles.json")
        let store = JSONProfileStore(fileURL: fileURL)

        let initial = try store.load()
        check(initial.profiles.isEmpty, "fresh load has no profiles")
        check(initial.version == 12, "fresh file is written at version 12")
        check(initial.keepOpenBundleIds.isEmpty, "fresh load has an empty Keep open list")
        check(initial.snapshots.isEmpty, "fresh load has no snapshots")
        check(FileManager.default.fileExists(atPath: fileURL.path), "fresh load writes the file")

        var profile = Profile(name: "Day job", colorId: ProfileColor.plum.rawValue)
        profile.items = [
            .app(bundleId: "com.figma.Desktop", name: "Figma"),
            .chromeProfile(directory: "Profile 1", displayName: "Work"),
            .link(url: "https://claude.ai/project/abc", title: "Claude"),
            .folder(path: "/Users/me/proj", appBundleId: "com.microsoft.VSCode", appName: "Code"),
            .folder(path: "/Users/me/refs"),
            ProfileItem(
                type: .folder,
                path: "/Users/me/dev",
                appBundleId: Constants.terminalBundleID,
                appName: "Terminal",
                startupCommand: "npm run dev"
            )
        ]
        profile.groupOrder = [.apps, .folders, .chromeWithLinks]
        var claude = ProfileItem.app(bundleId: Constants.claudeBundleID, name: "Claude")
        claude.destination = .claude(kind: .project, id: "01a038d1-3432-760e-b200-bc866ee41497")
        profile.items.append(claude)

        let session = ActiveSession(
            profileId: profile.id,
            startedAt: Date(),
            baselineBundleIds: ["com.apple.finder"]
        )
        try store.save(
            StoreFile(
                version: 3,
                profiles: [profile],
                activeSession: session,
                keepOpenBundleIds: ["com.tinyspeck.slackmacgap"]
            )
        )

        let reloaded = try store.load()
        check(reloaded.profiles.count == 1, "one profile survives a round trip")
        check(reloaded.profiles.first?.items.count == 7, "all item kinds survive")
        check(reloaded.profiles.first?.groupOrder == [.apps, .folders, .chromeWithLinks], "group order survives")
        check(reloaded.activeSession?.baselineBundleIds == ["com.apple.finder"], "baseline survives")
        check(reloaded.profiles.first?.colorId == ProfileColor.plum.rawValue, "the colour survives")
        check(reloaded.keepOpenBundleIds == ["com.tinyspeck.slackmacgap"], "the Keep open list survives")
        check(reloaded.profiles.first?.items.first?.destination == nil, "an app without a destination stays empty")
        let claudeItem = reloaded.profiles.first?.items.first { $0.bundleId == Constants.claudeBundleID }
        check(
            claudeItem?.destination == .claude(
                kind: .project,
                id: "01a038d1-3432-760e-b200-bc866ee41497"
            ),
            "a Claude destination survives"
        )

        let folderWithoutApp = reloaded.profiles.first?.items[4]
        check(folderWithoutApp?.appBundleId == nil, "a folder can have no opener")
        check(folderWithoutApp?.opensInLabel == "Opens in Finder", "no opener reads as Finder")

        let terminalApp = reloaded.profiles.first?.items.first {
            $0.bundleId == Constants.terminalBundleID
        }
        check(terminalApp?.terminalTabs?.first?.command == "npm run dev", "terminal tab command survives migration")
        check(
            reloaded.profiles.first?.items.contains(where: {
                $0.type == .folder && $0.appBundleId == Constants.terminalBundleID
            }) == false,
            "terminal folders become tabs"
        )

        // The file is meant to be hand-edited, so it has to stay readable.
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        check(text.contains("\n  \"profiles\""), "file is pretty printed")
        check(text.contains("https://claude.ai/project/abc"), "urls are not escaped into gibberish")
        check(text.contains("\"kind\""), "Claude destinations store a kind")
        check(text.contains("\"id\""), "Claude destinations store an id, not the pasted string")
        check(!text.contains("desktopProject"), "the old desktopProject key is not written")
        check(!text.contains("claudeID"), "the old claudeID key is not written")
        check(text.contains("terminalTabs"), "terminal tabs are written to disk")
    }

    static func migrationFromV7(in dir: URL) throws {
        let folderID = "F011D000-0000-4000-8000-000000000099"
        let v7 = """
        {
          "version": 7,
          "profiles": [
            {
              "id": "8B3D4E1A-0000-4000-8000-000000000099",
              "name": "Dev",
              "colorId": "forest",
              "items": [
                {
                  "id": "\(folderID)",
                  "type": "folder",
                  "path": "/Users/me/forkline",
                  "appBundleId": "\(Constants.terminalBundleID)",
                  "appName": "Terminal",
                  "startupCommand": "npm run dev"
                }
              ]
            }
          ],
          "keepOpenBundleIds": []
        }
        """
        let fileURL = dir.appendingPathComponent("v7-terminal.json")
        try v7.write(to: fileURL, atomically: true, encoding: .utf8)
        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()
        check(migrated.version == 12, "a v7 file loads as v12")
        let profile = migrated.profiles.first
        check(profile?.items.count == 1, "terminal folder becomes one app row")
        check(profile?.items.first?.bundleId == Constants.terminalBundleID, "a Terminal app row is created")
        check(profile?.items.first?.terminalTabs?.count == 1, "one tab is migrated")
        check(profile?.items.first?.terminalTabs?.first?.path == "/Users/me/forkline", "tab keeps the folder path")
        check(profile?.items.first?.terminalTabs?.first?.command == "npm run dev", "tab keeps the command")
    }

    static func migration(in dir: URL) throws {
        // A real v1 file: handoff notes, the old item spellings, and the editor
        // name written into `name` on a folder.
        let v1 = """
        {
          "version": 1,
          "profiles": [
            {
              "id": "8B3D4E1A-0000-4000-8000-000000000001",
              "name": "Startup",
              "items": [
                { "type": "app", "bundleId": "com.figma.Desktop", "name": "Figma" },
                { "type": "chromeAccount", "directory": "Profile 3", "displayName": "Personal" },
                { "type": "url", "url": "https://linear.app/team", "title": "Linear" },
                { "type": "folder", "path": "/Users/me/proj", "appBundleId": "com.microsoft.VSCode", "appName": "Code", "name": "Code" }
              ],
              "notes": [{ "text": "Stopped on billing", "endedAt": "2026-09-17T10:00:00Z", "skipped": false }],
              "lastNoteSkipped": false,
              "lastSessionUnclean": true
            }
          ]
        }
        """
        let fileURL = dir.appendingPathComponent("v1.json")
        try v1.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()

        check(migrated.version == 12, "a v1 file loads as v12")
        check(migrated.profiles.count == 1, "migration keeps the profile")
        let profile = migrated.profiles.first
        check(profile?.name == "Startup", "migration keeps the name")
        check(profile?.items.count == 4, "migration keeps every item")
        check(profile?.chromeProfile?.displayName == "Personal", "chromeAccount becomes chromeProfile")
        check(profile?.links.first?.url == "https://linear.app/team", "url becomes link")
        check(profile?.groupOrder == ItemGroup.defaultOrder, "migration fills in the group order")

        // v1 wrote the editor name into `name`, which would now render as the
        // row title. The folder name has to come from the path instead.
        let folder = profile?.items(in: .folders).first
        check(folder?.label == "proj", "a migrated folder is titled by its path")
        check(folder?.appName == "Code", "a migrated folder keeps its opener")

        let rewritten = try String(contentsOf: fileURL, encoding: .utf8)
        check(!rewritten.contains("notes"), "notes are gone from the rewritten file")
        check(!rewritten.contains("lastSessionUnclean"), "unclean flag is gone from the rewritten file")
        check(!rewritten.contains("chromeAccount"), "the old kind spelling is gone")
        check(rewritten.contains("\"version\" : 12"), "the file says version 12")
        check(migrated.snapshots.isEmpty, "a v1 file gains an empty snapshot list")

        // A file that predates colours must come out with one, or its card has no
        // background to draw.
        check(profile?.colorId.isEmpty == false, "migration assigns a colour")
        check(ProfileColor(rawValue: profile?.colorId ?? "") != nil, "the assigned colour is in the palette")

        // Loading the rewritten file must be a no-op, not a second migration.
        let again = try store.load()
        check(again.profiles.first?.items.count == 4, "the rewritten file reloads unchanged")
        check(again.profiles.first?.colorId == profile?.colorId, "the colour is stable across reloads")
    }

    /// v2 shipped without colours, so its files need the same treatment as v1
    /// without being re-migrated in any other respect.
    static func migrationFromV2(in dir: URL) throws {
        let v2 = """
        {
          "version": 2,
          "profiles": [
            { "id": "8B3D4E1A-0000-4000-8000-000000000011", "name": "One", "items": [], "groupOrder": ["chromeWithLinks", "apps", "folders"] },
            { "id": "8B3D4E1A-0000-4000-8000-000000000012", "name": "Two", "items": [] },
            { "id": "8B3D4E1A-0000-4000-8000-000000000013", "name": "Three", "items": [], "colorId": "clay" }
          ]
        }
        """
        let fileURL = dir.appendingPathComponent("v2.json")
        try v2.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()

        check(migrated.version == 12, "a v2 file loads as v12")
        check(migrated.profiles.count == 3, "migration keeps every profile")
        check(migrated.keepOpenBundleIds.isEmpty, "a v2 file gains an empty Keep open list")

        let ids = migrated.profiles.map(\.colorId)
        check(ids.allSatisfy { ProfileColor(rawValue: $0) != nil }, "every profile ends up with a real colour")
        check(ids[2] == "wine", "a colour already chosen is kept (migrated to V8)")
        // Distinct colours are the point: three identical cards would defeat it.
        check(Set(ids).count == 3, "migrated profiles get distinct colours")
    }

    /// v3 opened Claude destinations as Chrome tabs. Those have to become
    /// desktop destinations without losing the link.
    static func migrationFromV3(in dir: URL) throws {
        let v3 = """
        {
          "version": 3,
          "profiles": [
            {
              "id": "8B3D4E1A-0000-4000-8000-000000000021",
              "name": "Work",
              "colorId": "forest",
              "items": [
                {
                  "type": "app",
                  "bundleId": "com.anthropic.claudefordesktop",
                  "name": "Claude",
                  "destination": { "webProject": { "url": "https://claude.ai/project/01a038d1-3432-760e-b200-bc866ee41497" } }
                }
              ]
            }
          ],
          "keepOpenBundleIds": []
        }
        """
        let fileURL = dir.appendingPathComponent("v3.json")
        try v3.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()

        check(migrated.version == 12, "a v3 file loads as v12")
        let destination = migrated.profiles.first?.items.first?.destination
        check(
            destination == .claude(kind: .project, id: "01a038d1-3432-760e-b200-bc866ee41497"),
            "a v3 Claude project URL becomes kind and id"
        )
    }

    /// v4 stored a full Claude URL as desktopProject. The kind and id are
    /// unpacked from the path on load.
    static func migrationFromV4(in dir: URL) throws {
        let id = "01a038d1-3432-760e-b200-bc866ee41497"
        let v4 = """
        {
          "version": 4,
          "profiles": [
            {
              "id": "8B3D4E1A-0000-4000-8000-000000000031",
              "name": "Work",
              "colorId": "forest",
              "items": [
                {
                  "type": "app",
                  "bundleId": "com.anthropic.claudefordesktop",
                  "name": "Claude",
                  "destination": { "desktopProject": { "url": "https://claude.ai/chat/\(id)" } }
                }
              ]
            }
          ],
          "keepOpenBundleIds": []
        }
        """
        let fileURL = dir.appendingPathComponent("v4.json")
        try v4.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()

        check(migrated.version == 12, "a v4 file loads as v12")
        let destination = migrated.profiles.first?.items.first?.destination
        check(
            destination == .claude(kind: .chat, id: id),
            "a v4 desktop chat URL is unpacked into kind and id"
        )
    }

    static func migrationFromV5(in dir: URL) throws {
        let v5 = """
        {
          "version": 5,
          "profiles": [
            {
              "id": "8B3D4E1A-0000-4000-8000-000000000041",
              "name": "Work",
              "colorId": "forest",
              "items": []
            }
          ],
          "keepOpenBundleIds": []
        }
        """
        let fileURL = dir.appendingPathComponent("v5.json")
        try v5.write(to: fileURL, atomically: true, encoding: .utf8)
        let store = JSONProfileStore(fileURL: fileURL)
        let migrated = try store.load()
        check(migrated.version == 12, "a v5 file loads as v12")
        check(migrated.snapshots.isEmpty, "a v5 file gains an empty snapshot list")
        check(migrated.profiles.count == 1, "a v5 profile survives")
    }

    // MARK: - Model rules

    static func links() {
        check(ProfileItem.normalizedURL("linkedin.com/in/me") == "https://linkedin.com/in/me", "a bare host gains https")
        check(ProfileItem.normalizedURL("  https://figma.com/file/1 ") == "https://figma.com/file/1", "whitespace is trimmed")
        check(ProfileItem.normalizedURL("http://localhost.dev") == "http://localhost.dev", "http is accepted")
        check(ProfileItem.normalizedURL("ftp://files.example.com") == nil, "other schemes are refused")
        check(ProfileItem.normalizedURL("not a url") == nil, "nonsense is refused")
        check(ProfileItem.normalizedURL("") == nil, "empty is refused")

        // A blank title falls back to the host, with no network call.
        let url = ProfileItem.normalizedURL("www.linkedin.com/in/me")!
        check(ProfileItem.host(of: url) == "linkedin.com", "www is dropped from the host")
        check(ProfileItem.link(url: url, title: "").label == "linkedin.com", "a blank title shows the host")
        check(ProfileItem.link(url: url, title: "Profile").label == "Profile", "a typed title wins")
    }

    static func rowCopy() {
        // A subtitle exists only where an item opens somewhere specific.
        check(ProfileItem.app(bundleId: "com.apple.Music", name: "Music").subtitle == nil, "a bare app has no subtitle")
        check(ProfileItem.chromeProfile(directory: "Profile 1", displayName: "Work").subtitle == nil, "chrome has no subtitle")
        check(ProfileItem.link(url: "https://figma.com/f/1", title: "Spec").subtitle == "figma.com", "a link shows its host")

        let folder = ProfileItem.folder(path: NSHomeDirectory() + "/Projects/maal", appBundleId: "x", appName: "Cursor")
        check(folder.label == "maal", "a folder is titled by its own name, not its opener")
        check(folder.subtitle?.hasPrefix("~/") == true, "a folder path is abbreviated with a tilde")
        check(folder.opensInLabel == "Opens in Cursor", "a folder says where it opens")

        let terminalApp = ProfileItem.app(
            bundleId: Constants.terminalBundleID,
            name: "Terminal",
            terminalTabs: [TerminalTab(path: "/tmp/forkline", command: "npm run dev")]
        )
        check(terminalApp.terminalRowSummary?.contains("forkline: npm run dev") == true, "terminal row summary shows tabs")
    }

    static func closeTargets() {
        // Links ride inside Chrome and Finder is the system, so neither is ever
        // asked to quit.
        check(ProfileItem.link(url: "https://x.com", title: "x").closeBundleId == nil, "links are not closed")
        check(
            ProfileItem.folder(path: "/tmp", appBundleId: Constants.finderBundleID, appName: "Finder").closeBundleId == nil,
            "Finder is never asked to quit"
        )
        check(ProfileItem.folder(path: "/tmp").closeBundleId == nil, "a Finder folder has nothing to close")
        check(
            ProfileItem.folder(path: "/tmp", appBundleId: "com.microsoft.VSCode", appName: "Code").closeBundleId == "com.microsoft.VSCode",
            "a folder closes the editor it opened"
        )
        check(
            ProfileItem.chromeProfile(directory: "Profile 1", displayName: "Work").closeBundleId == ChromeService.chromeBundleID,
            "a chrome profile closes Chrome"
        )

        // Ending a session clears every app not on never-close (no baseline exemption).
        check(
            RoleTeardown.action(for: "com.apple.Music", incomingOwned: [], neverClose: []) == .minimize,
            "VLC-like apps are minimized when not in the role"
        )
        check(
            RoleTeardown.action(for: Constants.figmaBundleID, incomingOwned: [], neverClose: []) == .minimize,
            "non-role apps are minimized (V6)"
        )
        check(
            RoleTeardown.action(for: Constants.terminalBundleID, incomingOwned: [], neverClose: []) == .minimize,
            "Terminal is minimized, never quit"
        )
    }

    static func groupOrder() {
        check(ItemGroup.defaultOrder.first == .chromeWithLinks, "Chrome opens first, since it is slowest to start")
        check(Profile.normalized([]) == ItemGroup.defaultOrder, "an empty order falls back to the default")
        check(
            Profile.normalized([.folders, .folders]) == [.folders, .chromeWithLinks, .apps],
            "a partial hand-written order is completed without duplicates"
        )

        var profile = Profile(name: "Mixed")
        profile.items = [
            .link(url: "https://a.com", title: "A"),
            .app(bundleId: "one", name: "One"),
            .chromeProfile(directory: "Profile 1", displayName: "Work"),
            .app(bundleId: "two", name: "Two")
        ]
        check(profile.items(in: .apps).map(\.label) == ["One", "Two"], "apps read in list order")
        check(profile.items(in: .chromeWithLinks).count == 1, "the chrome group holds only the chrome profile")
        check(profile.links.count == 1, "links are their own list")
        check(profile.chromeProfile?.label == "Work", "the chrome profile is found by name")
    }

    static func colours() {
        check(ProfileColor.allCases.count == 6, "the palette has exactly six colours")
        check(ProfileColor.named("slate") == .slate, "a known id resolves")
        // A hand-edited file with a typo must still open.
        check(ProfileColor.named("chartreuse") == .fallback, "an unknown id falls back")
        check(ProfileColor.named(nil) == .fallback, "a missing id falls back")
        check(
            ProfileColor.allCases.map(\.hex) == ["26296E", "2B4752", "4C412F", "69212F", "3E1851", "953D53"],
            "V8 palette hex values in order"
        )
        let legacy: [(String, ProfileColor)] = [
            ("indigo", .navy), ("teal", .slate), ("bronze", .bronze),
            ("clay", .wine), ("violet", .plum), ("forest", .rose)
        ]
        for (old, new) in legacy {
            check(ProfileColor.named(old) == new, "pre-V8 \(old) shows as \(new.displayName)")
        }

        let existing = [
            Profile(name: "A", colorId: ProfileColor.navy.rawValue),
            Profile(name: "B", colorId: "teal")
        ]
        check(ProfileColor.firstUnused(in: existing) == .bronze, "a new profile takes the first free colour")
        check(ProfileColor.firstUnused(in: []) == .navy, "the first profile takes the first colour")

        // All six taken means falling back to the first, not failing. Sharing a
        // colour is allowed, just never the default.
        let all = ProfileColor.allCases.map { Profile(name: $0.rawValue, colorId: $0.rawValue) }
        check(ProfileColor.firstUnused(in: all) == .navy, "with every colour taken the first is reused")

        var file = StoreFile(version: 10, profiles: [
            Profile(name: "Old", colorId: "clay"),
            Profile(name: "New", colorId: "rose"),
            Profile(name: "Odd", colorId: "chartreuse")
        ], activeSession: nil)
        check(JSONProfileStore.migratePreV8Colours(in: &file), "pre-V8 colours are migrated")
        check(file.profiles.map(\.colorId) == ["wine", "rose", "chartreuse"], "only pre-V8 ids are rewritten")
    }

    static func destinations() {
        let p = "01a038d1-3432-760e-b200-bc866ee41497"
        let c = "11b149e2-4543-871f-c311-cd977ff52508"

        func ok(_ input: String, kind: ClaudeLinkKind, id: String, _ label: String) {
            switch ClaudeService.parse(input) {
            case .success(let parsed):
                check(parsed.kind == kind && parsed.id == id, label)
            case .failure(let error):
                check(false, "\(label) (got \(error))")
            }
        }
        func fail(_ input: String, _ expected: ClaudeService.ParseError, _ label: String) {
            switch ClaudeService.parse(input) {
            case .failure(let error):
                check(error == expected, label)
            case .success:
                check(false, "\(label) (got success)")
            }
        }
        func message(_ input: String) -> String? {
            switch ClaudeService.parse(input) {
            case .success: return "success"
            case .failure(let error): return error.message
            }
        }

        ok("https://claude.ai/project/\(p)", kind: .project, id: p, "https project link")
        ok("https://claude.ai/chat/\(c)", kind: .chat, id: c, "https chat link")
        ok("http://claude.ai/chat/\(c)", kind: .chat, id: c, "http chat link")
        ok("https://www.claude.ai/project/\(p)", kind: .project, id: p, "www is stripped")
        ok("claude://claude.ai/chat/\(c)", kind: .chat, id: c, "claude:// chat link")
        ok("claude.ai/project/\(p)", kind: .project, id: p, "scheme-less project link")
        ok("  https://claude.ai/chat/\(c)  ", kind: .chat, id: c, "surrounding whitespace")
        ok("https://claude.ai/chat/\(c)/", kind: .chat, id: c, "trailing slash")
        ok("https://claude.ai/chat/\(c)?q=hello", kind: .chat, id: c, "query is discarded")
        ok("https://claude.ai/chat/\(c)#top", kind: .chat, id: c, "fragment is discarded")
        ok("https://claude.ai/project/\(p.uppercased())", kind: .project, id: p, "id is stored lowercased")

        let s = "session_01JFqGb6pqXoRHSGWnsydieG"
        let cse = "cse_01AbCDefGHijKLmnOPqrST"
        ok("https://claude.ai/cowork/project/\(p)", kind: .cowork, id: p, "https cowork link")
        ok("claude://claude.ai/cowork/project/\(p)", kind: .cowork, id: p, "claude:// cowork link")
        ok("claude.ai/cowork/project/\(p)", kind: .cowork, id: p, "scheme-less cowork link")
        ok("https://www.claude.ai/cowork/project/\(p)/", kind: .cowork, id: p, "www cowork trailing slash")
        ok("https://claude.ai/cowork/project/\(p.uppercased())", kind: .cowork, id: p, "cowork id is stored lowercased")
        ok("https://claude.ai/cowork/\(p)", kind: .cowork, id: p, "short cowork link is accepted")
        ok("claude://claude.ai/cowork/\(p)", kind: .cowork, id: p, "short claude:// cowork link")
        ok("claude.ai/cowork/\(p)", kind: .cowork, id: p, "scheme-less short cowork link")
        ok("https://www.claude.ai/cowork/\(p)/", kind: .cowork, id: p, "www short cowork trailing slash")
        ok(p, kind: .cowork, id: p, "bare UUID means cowork")
        ok(p.uppercased(), kind: .cowork, id: p, "bare UUID is stored lowercased")
        ok(s, kind: .code, id: s, "bare session_ ID means code")
        ok(cse, kind: .code, id: cse, "bare cse_ ID means code")
        ok("https://claude.ai/code/\(s)", kind: .code, id: s, "https code link keeps case")
        ok("claude://claude.ai/code/\(s)", kind: .code, id: s, "claude:// code link keeps case")
        ok("claude.ai/code/\(s)", kind: .code, id: s, "scheme-less code link keeps case")
        ok("https://www.claude.ai/code/\(s)/", kind: .code, id: s, "www code trailing slash keeps case")
        ok("  https://claude.ai/code/\(s)?ref=x  ", kind: .code, id: s, "code query and whitespace keep case")
        ok("https://claude.ai/code/\(cse)", kind: .code, id: cse, "a cse_ code id is accepted")

        let share = "b89b7689-4dc0-41e1-9d82-f2a8bcae0217"
        fail("https://claude.ai/share/\(share)", .shareLink, "a share link is refused")
        fail("claude.ai/share/\(share)", .shareLink, "scheme-less share link is refused")
        check(
            message("https://claude.ai/share/\(share)")
                == "This is a share link. It opens a read-only copy, not your conversation. Paste the conversation's own link instead (it contains /chat/, /cowork/ or /code/).",
            "share link has its own message"
        )

        fail("https://claude.ai/chat/new", .newChat, "a new chat is refused")
        fail("https://claude.ai/cowork/project/not-a-uuid", .noID, "a non-uuid cowork path is refused")
        fail("https://claude.ai/cowork/project/", .noID, "a cowork path without an id is refused")
        fail("https://claude.ai/code/notasession", .noID, "a non-session code path is refused")
        fail("https://claude.ai/code/session_", .noID, "an empty session_ prefix is refused")
        fail("https://claude.ai/code/local_abc-def", .noID, "a local_ code id is refused")
        fail("https://claude.ai/code/", .noID, "a code path without an id is refused")
        fail("https://example.com/code/\(s)", .wrongHost, "a foreign host on a code path is refused")
        fail("https://claude.ai.evil.com/code/\(s)", .wrongHost, "a suffix host on a code path is refused")
        fail("https://example.com/cowork/project/\(p)", .wrongHost, "a foreign host on a cowork path is refused")
        fail("https://claude.ai/cowork/", .noID, "a short cowork path without an id is refused")
        fail("https://claude.ai/cowork/not-a-uuid", .noID, "a short cowork path with an invalid id is refused")
        fail("https://claude.ai/recents", .noKind, "recents has no kind")
        fail("https://claude.ai/", .noKind, "the homepage has no kind")
        fail("https://claude.ai/chat/not-a-uuid", .noID, "a non-uuid chat path is refused")
        fail("https://claude.ai/chat/12345", .noID, "a numeric chat path is refused")
        fail("https://example.com/chat/\(c)", .wrongHost, "a foreign host is refused")
        fail("https://notclaude.ai/chat/\(c)", .wrongHost, "a lookalike host is refused")
        fail("https://claude.ai.evil.com/chat/\(c)", .wrongHost, "a suffix host is refused")
        fail("", .empty, "empty input is empty, not a message")
        fail("not a url at all", .wrongHost, "nonsense is a wrong host")

        check(message("") == nil, "empty input has no error string")
        check(message("https://example.com/chat/\(c)") == "That isn't a Claude link.", "wrong host has its own message")
        check(
            message("https://claude.ai/recents")
                == "Paste a link, a Cowork UUID, or a session_ / cse_ id.",
            "no kind has its own message"
        )
        check(
            message("https://claude.ai/chat/new")
                == "That's a new chat, not a saved one. Open the conversation first, then copy its link.",
            "new chat has its own message"
        )
        check(
            message("https://claude.ai/chat/not-a-uuid")
                == "That link doesn't have a valid id in it.",
            "missing id has its own message"
        )

        check(
            ClaudeService.desktopURL(kind: .project, id: p)?.absoluteString == "claude://claude.ai/project/\(p)",
            "a project builds claude://claude.ai/project/<id>"
        )
        check(
            ClaudeService.desktopURL(kind: .chat, id: c)?.absoluteString == "claude://claude.ai/chat/\(c)",
            "a chat builds claude://claude.ai/chat/<id>"
        )
        check(
            ClaudeService.desktopURL(kind: .cowork, id: p)?.absoluteString
                == "claude://claude.ai/cowork/\(p)",
            "a cowork destination builds /cowork/<id>"
        )
        check(
            ClaudeService.httpsURL(kind: .cowork, id: p)
                == "https://claude.ai/cowork/\(p)",
            "a cowork https fallback uses /cowork/<id>"
        )
        check(
            ClaudeService.desktopURL(kind: .code, id: s)?.absoluteString == "claude://claude.ai/code/\(s)",
            "a code destination keeps the session case"
        )
        check(
            ClaudeService.desktopURL(kind: .code, id: s.lowercased())?.absoluteString
                != ClaudeService.desktopURL(kind: .code, id: s)?.absoluteString,
            "lowercasing a code id produces a different URL"
        )
        check(ClaudeService.desktopURL(kind: .project, id: "not-a-uuid") == nil, "an invalid id is not built")
        check(ClaudeService.desktopURL(kind: .code, id: p) == nil, "a UUID is not a code id")

        var claude = ProfileItem.app(bundleId: Constants.claudeBundleID, name: "Claude")
        claude.destination = .claude(kind: .project, id: p)
        check(claude.subtitle?.hasPrefix("Opens a project") == true, "a project destination reads as a project")
        check(!(claude.subtitle ?? "").contains(p), "the UUID is never shown")

        var chat = ProfileItem.app(bundleId: Constants.claudeBundleID, name: "Claude")
        chat.destination = .claude(kind: .chat, id: c)
        check(chat.subtitle?.hasPrefix("Opens a conversation") == true, "a chat destination reads as a conversation")
        check(!(chat.subtitle ?? "").contains(c), "the chat UUID is never shown")

        var cowork = ProfileItem.app(bundleId: Constants.claudeBundleID, name: "Claude")
        cowork.destination = .claude(kind: .cowork, id: p)
        check(cowork.subtitle?.hasPrefix("Opens a Cowork session") == true, "a cowork destination reads as Cowork")
        check(!(cowork.subtitle ?? "").contains(p), "the cowork UUID is never shown")

        var code = ProfileItem.app(bundleId: Constants.claudeBundleID, name: "Claude")
        code.destination = .claude(kind: .code, id: s)
        check(code.subtitle?.hasPrefix("Opens a Claude Code session") == true, "a code destination reads as Code")
        check(!(code.subtitle ?? "").contains(s), "the session id is never shown")

        check(claude.closeBundleId == Constants.claudeBundleID, "a destination does not affect closing")

        if ClaudeService.isInstalled() {
            var profile = Profile(name: "Desktop")
            profile.items = [claude, .link(url: "https://linear.app", title: "Linear")]
            check(profile.browserDestinationURLs.isEmpty, "a Desktop destination is not sent to Chrome")
        }

        let oldClaudeJSON = Data("{\"claude\":{\"claudeID\":\"\(p)\"}}".utf8)
        if let decoded = try? JSONDecoder().decode(ItemDestination.self, from: oldClaudeJSON) {
            check(decoded == .claude(kind: .project, id: p), "a stored UUID without a kind is a project")
        } else {
            check(false, "a stored UUID without a kind is a project")
        }

        let newShape = Data("{\"claude\":{\"kind\":\"chat\",\"id\":\"\(c)\"}}".utf8)
        if let decoded = try? JSONDecoder().decode(ItemDestination.self, from: newShape) {
            check(decoded == .claude(kind: .chat, id: c), "the kind/id shape round-trips")
        } else {
            check(false, "the kind/id shape round-trips")
        }

        let codeShape = Data("{\"claude\":{\"kind\":\"code\",\"id\":\"\(s)\"}}".utf8)
        if let decoded = try? JSONDecoder().decode(ItemDestination.self, from: codeShape) {
            check(decoded == .claude(kind: .code, id: s), "a stored code id keeps its case")
        } else {
            check(false, "a stored code id keeps its case")
        }

        let coworkShape = Data("{\"claude\":{\"kind\":\"cowork\",\"id\":\"\(p)\"}}".utf8)
        if let decoded = try? JSONDecoder().decode(ItemDestination.self, from: coworkShape) {
            check(decoded == .claude(kind: .cowork, id: p), "a stored cowork destination round-trips")
        } else {
            check(false, "a stored cowork destination round-trips")
        }

        let unknownKindJSON = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","type":"app","bundleId":"com.anthropic.claudefordesktop","name":"Claude","destination":{"claude":{"kind":"not-a-kind","id":"\(p)"}}}
        """.utf8)
        if let decoded = try? JSONDecoder().decode(ProfileItem.self, from: unknownKindJSON) {
            check(decoded.destination == nil, "an unknown destination kind is dropped")
            check(decoded.bundleId == "com.anthropic.claudefordesktop", "the item survives a bad destination")
        } else {
            check(false, "an unknown destination kind is dropped")
        }
    }

    static func figmaDestinations() {
        let k = "AbC123xyz789AbC123xyz7"
        let mixed = "MiXeDcAsEkEyAbC123xyz7"

        func ok(
            _ input: String,
            kind: FigmaFileKind,
            fileKey: String,
            slug: String?,
            nodeId: String?,
            _ label: String
        ) {
            switch FigmaService.parse(input) {
            case .success(let parsed):
                check(
                    parsed.kind == kind
                        && parsed.fileKey == fileKey
                        && parsed.slug == slug
                        && parsed.nodeId == nodeId,
                    label
                )
            case .failure(let error):
                check(false, "\(label) (got \(error))")
            }
        }
        func fail(_ input: String, _ expected: FigmaService.ParseError, _ label: String) {
            switch FigmaService.parse(input) {
            case .failure(let error):
                check(error == expected, label)
            case .success:
                check(false, "\(label) (got success)")
            }
        }
        func message(_ input: String) -> String? {
            switch FigmaService.parse(input) {
            case .success: return "success"
            case .failure(let error): return error.message
            }
        }

        ok(
            "https://www.figma.com/design/\(k)/My-File?node-id=1-234",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234",
            "https design link with node"
        )
        ok(
            "https://www.figma.com/design/\(k)/My-File?node-id=1%3A234",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1%3A234",
            "encoded node id is stored undecoded"
        )
        ok(
            "https://figma.com/design/\(k)/My-File?node-id=1-234",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234",
            "www is not required"
        )
        ok(
            "https://www.figma.com/design/\(k)/My-File",
            kind: .design, fileKey: k, slug: "My-File", nodeId: nil,
            "a file link with no node"
        )
        ok(
            "https://www.figma.com/design/\(k)",
            kind: .design, fileKey: k, slug: nil, nodeId: nil,
            "a file link with no slug"
        )
        ok(
            "https://www.figma.com/file/\(k)/Old?node-id=1-234",
            kind: .file, fileKey: k, slug: "Old", nodeId: "1-234",
            "file kind is preserved"
        )
        ok(
            "https://www.figma.com/board/\(k)/Jam",
            kind: .board, fileKey: k, slug: "Jam", nodeId: nil,
            "board kind"
        )
        ok(
            "https://www.figma.com/slides/\(k)/Deck",
            kind: .slides, fileKey: k, slug: "Deck", nodeId: nil,
            "slides kind"
        )
        ok(
            "https://www.figma.com/proto/\(k)/P?node-id=1-234",
            kind: .proto, fileKey: k, slug: "P", nodeId: "1-234",
            "proto kind"
        )
        ok(
            "figma://design/\(k)/My-File?node-id=1-234",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234",
            "figma:// design link"
        )
        ok(
            "figma.com/design/\(k)/My-File",
            kind: .design, fileKey: k, slug: "My-File", nodeId: nil,
            "scheme-less figma link"
        )
        ok(
            "  https://www.figma.com/design/\(k)/My-File/  ",
            kind: .design, fileKey: k, slug: "My-File", nodeId: nil,
            "whitespace and trailing slash"
        )
        ok(
            "https://www.figma.com/design/\(k)/My-File?node-id=1-234&t=aBc123-0",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234",
            "share token is stripped"
        )
        ok(
            "https://www.figma.com/design/\(k)/My-File?viewport=1%2C2%2C3&node-id=1-234",
            kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234",
            "viewport is stripped, node kept"
        )
        ok(
            "https://www.figma.com/design/\(mixed)/F",
            kind: .design, fileKey: mixed, slug: "F", nodeId: nil,
            "file key case is preserved"
        )

        fail("https://www.figma.com/design/short/F", .noKey, "a short key is refused")
        fail("https://www.figma.com/design/", .noKey, "a design path without a key is refused")
        fail("https://www.figma.com/settings", .noKind, "settings is not a file kind")
        fail("https://www.figma.com/", .noKind, "the homepage has no kind")
        fail("https://example.com/design/\(k)/F", .wrongHost, "a foreign host is refused")
        fail("https://figma.com.evil.com/design/\(k)/F", .wrongHost, "a suffix host is refused")
        fail("https://notfigma.com/design/\(k)/F", .wrongHost, "a lookalike host is refused")
        fail("https://www.figma.com/design/\(k)/branch/\(k)", .noKey, "a branch URL is not a destination")
        fail("", .empty, "empty input is empty, not a message")

        check(message("") == nil, "empty figma input has no error string")
        check(message("https://example.com/design/\(k)/F") == "That isn't a Figma link.", "wrong host has its own message")
        check(message("https://www.figma.com/settings") == "Paste a link to a Figma file.", "no kind has its own message")
        check(message("https://www.figma.com/design/") == "That link doesn't have a Figma file in it.", "missing key has its own message")

        let withToken = FigmaService.parse("https://www.figma.com/design/\(k)/My-File?node-id=1-234&t=aBc123-0")
        if case .success(let parsed) = withToken {
            let https = FigmaService.httpsURL(kind: parsed.kind, fileKey: parsed.fileKey, slug: parsed.slug, nodeId: parsed.nodeId)
            let desktop = FigmaService.desktopURL(kind: parsed.kind, fileKey: parsed.fileKey, slug: parsed.slug, nodeId: parsed.nodeId)?.absoluteString ?? ""
            check(!https.contains("t="), "the https rebuild has no share token")
            check(!desktop.contains("t="), "the desktop rebuild has no share token")
            check(
                https == "https://www.figma.com/design/\(k)/My-File?node-id=1-234",
                "https rebuilds without extra query items"
            )
            check(
                desktop == "figma://design/\(k)/My-File?node-id=1-234",
                "desktop is a scheme swap of the same path"
            )
        } else {
            check(false, "https rebuilds without extra query items")
        }

        let encodedNode = FigmaService.parse("https://www.figma.com/design/\(k)/My-File?node-id=1%3A234")
        if case .success(let parsed) = encodedNode {
            let https = FigmaService.httpsURL(kind: parsed.kind, fileKey: parsed.fileKey, slug: parsed.slug, nodeId: parsed.nodeId)
            check(parsed.nodeId == "1%3A234", "the stored node id keeps percent encoding")
            check(https.contains("node-id=1%3A234"), "the launched https URL keeps percent encoding")
            check(!https.contains("node-id=1:234"), "the launched URL is not decoded to a colon")
        } else {
            check(false, "the stored node id keeps percent encoding")
        }

        var page = ProfileItem.app(bundleId: Constants.figmaBundleID, name: "Figma")
        page.destination = .figma(kind: .design, fileKey: k, slug: "My-File", nodeId: "1-234")
        check(page.subtitle?.hasPrefix("Opens a page in My File") == true, "a node destination names the file")
        check(!(page.subtitle ?? "").contains(k), "the file key is never shown")
        check(!(page.subtitle ?? "").contains("1-234"), "the node id is never shown")

        var fileOnly = ProfileItem.app(bundleId: Constants.figmaBundleID, name: "Figma")
        fileOnly.destination = .figma(kind: .design, fileKey: k, slug: "My-File", nodeId: nil)
        check(fileOnly.subtitle?.hasPrefix("Opens My File") == true, "a file destination names the file")

        var noSlug = ProfileItem.app(bundleId: Constants.figmaBundleID, name: "Figma")
        noSlug.destination = .figma(kind: .design, fileKey: k, slug: nil, nodeId: nil)
        check(noSlug.subtitle?.hasPrefix("Opens a Figma file") == true, "a key-only destination has a generic subtitle")

        let stored = ItemDestination.figma(kind: .design, fileKey: mixed, slug: "F", nodeId: "1-234")
        if let data = try? JSONEncoder().encode(stored),
           let decoded = try? JSONDecoder().decode(ItemDestination.self, from: data) {
            check(decoded == stored, "a figma destination round-trips")
            if case .figma(_, let fileKey, _, _) = decoded {
                check(fileKey == mixed, "a stored file key keeps its case")
            }
        } else {
            check(false, "a figma destination round-trips")
        }

        let unknownKindJSON = Data("""
        {"id":"00000000-0000-0000-0000-000000000002","type":"app","bundleId":"com.figma.Desktop","name":"Figma","destination":{"notADestination":{"x":1}}}
        """.utf8)
        if let decoded = try? JSONDecoder().decode(ProfileItem.self, from: unknownKindJSON) {
            check(decoded.destination == nil, "an unknown figma destination is dropped")
            check(decoded.bundleId == Constants.figmaBundleID, "the figma item survives a bad destination")
        } else {
            check(false, "an unknown figma destination is dropped")
        }

        var profile = Profile(name: "Design")
        profile.items = [page]
        if FigmaService.isInstalled() {
            check(
                !profile.browserDestinationURLs.contains(where: { $0.contains("figma.com") }),
                "a Desktop Figma destination is not sent to Chrome"
            )
        } else {
            check(
                profile.browserDestinationURLs.contains(page.destination!.httpsURL),
                "a missing Figma app sends the https address to Chrome"
            )
        }
    }

    static func keepOpen() {
        var profile = Profile(name: "Day job")
        profile.items = [
            .app(bundleId: "com.figma.Desktop", name: "Figma"),
            .app(bundleId: "com.tinyspeck.slackmacgap", name: "Slack"),
            .chromeProfile(directory: "Profile 1", displayName: "Work")
        ]

        let keepOpen: Set<String> = ["com.tinyspeck.slackmacgap"]
        check(
            RoleTeardown.action(for: "com.tinyspeck.slackmacgap", incomingOwned: [], neverClose: keepOpen) == .skip,
            "an app on Keep open is never torn down"
        )
        check(
            RoleTeardown.action(for: "com.figma.Desktop", incomingOwned: [], neverClose: keepOpen) == .minimize,
            "other apps are still minimized"
        )
        check(
            RoleTeardown.action(
                for: "com.figma.Desktop",
                incomingOwned: [],
                neverClose: keepOpen,
                keep: ["com.figma.Desktop"]
            ) == .skip,
            "keep panel selection spares an app"
        )
        check(
            RoleTeardown.action(for: ChromeService.chromeBundleID, incomingOwned: [], neverClose: keepOpen) == .minimize,
            "Chrome is minimized when ending a session"
        )

        // Keep open grants immunity from closing only. It must never cause an app
        // to open, so the profile's own item list is untouched by it.
        check(profile.items.count == 3, "Keep open does not add anything to a profile")
    }

    static func chromeEntry() {
        // Whatever the user pastes, only the last path component matters.
        let full = "/Users/me/Library/Application Support/Google/Chrome/Profile 3"
        check(ChromeService.profileDirectoryName(fromPasted: full) == "Profile 3", "a full path yields the folder")
        check(
            ChromeService.profileDirectoryName(fromPasted: "Profile Path: \(full)") == "Profile 3",
            "the whole chrome://version line is accepted"
        )
        check(ChromeService.profileDirectoryName(fromPasted: full + "/") == "Profile 3", "a trailing slash is ignored")
        check(ChromeService.profileDirectoryName(fromPasted: "  Default  ") == "Default", "a bare folder name is accepted")
        check(ChromeService.profileDirectoryName(fromPasted: "\"\(full)\"") == "Profile 3", "surrounding quotes are stripped")
        check(ChromeService.profileDirectoryName(fromPasted: "") == nil, "empty input is refused")
        // One level too few: there is no profile called Chrome.
        check(
            ChromeService.profileDirectoryName(fromPasted: "/Users/me/Library/Application Support/Google/Chrome") == nil,
            "a path stopping at the Chrome folder is refused"
        )
    }

    /// Reports what this machine actually does, rather than asserting. The whole
    /// point of the typed result is that the answer differs by machine and by OS
    /// version, so a failure here would be meaningless.
    static func chromeDiagnostic() {
        let installed = ChromeService.isInstalled()
        print("\nchrome diagnostic")
        print("  installed: \(installed)")
        print("  path: \(ChromeService.installedPath()?.path ?? "not found")")

        switch ChromeService.profiles() {
        case .ok(let accounts):
            print("  result: readable, \(accounts.count) profile(s)")
            print("  the built-in list works on this machine")
        case .notInstalled:
            print("  result: Chrome is not installed")
        case .neverLaunched:
            print("  result: Chrome has never been launched")
        case .blockedBySystem:
            print("  result: blocked by the system")
            print("  manual entry is the only route; this is bug 18.1's cause")
        case .unreadable(let reason):
            print("  result: unreadable (\(reason))")
        }

        // Whatever the outcome, a pasted path must still resolve, because manual
        // entry is what the user falls back to.
        check(
            ChromeService.profileDirectoryName(fromPasted: "Profile 1") == "Profile 1",
            "manual entry works regardless of the diagnostic"
        )
    }

    // MARK: - AI assist

    static func aiProvider() {
        check(AIProvider.openaiVisionModel == "gpt-4o", "openai vision model is configured in one place")
        check(AIProvider.openaiKeyCheckModel == "gpt-4o-mini", "openai key-check model is configured in one place")
        check(AIProvider.deepseekTextModel == "deepseek-chat", "deepseek text model is configured in one place")
        check(AIProvider.openai.supportsVision, "openai supports vision")
        check(!AIProvider.deepseek.supportsVision, "deepseek does not support vision")
        check(AIKeyStatus.notSet.line == "Not set", "key status not set copy")
        check(AIKeyStatus.saved.line == "Saved", "key status saved copy")
        check(AIKeyStatus.rejected.line == "Saved, key rejected", "key status rejected copy")
    }

    static func matcherApps() -> [InstalledApp] {
        [
            InstalledApp(bundleId: "com.figma.Desktop", name: "Figma", url: URL(fileURLWithPath: "/Applications/Figma.app")),
            InstalledApp(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
            InstalledApp(bundleId: "com.microsoft.Word", name: "Microsoft Word", url: URL(fileURLWithPath: "/Applications/Microsoft Word.app")),
            InstalledApp(bundleId: "com.microsoft.Excel", name: "Microsoft Excel", url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app")),
            InstalledApp(bundleId: "com.apple.dt.Xcode", name: "Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app")),
            InstalledApp(bundleId: "com.google.Chrome", name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        ]
    }

    static func appMatcher() {
        let installed = matcherApps()
        let allowed = Set(installed.map(\.bundleId))

        let exact = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "figma", confidence: .high)],
            installed: installed
        )
        check(exact.matches.map(\.bundleId) == ["com.figma.Desktop"], "exact display name, case-insensitive")
        check(exact.unmatched.isEmpty, "exact match is not unmatched")

        let normalised = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Figma Desktop", confidence: .high)],
            installed: installed
        )
        check(normalised.matches.map(\.bundleId) == ["com.figma.Desktop"], "normalise strips desktop/punctuation")

        let prefix = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Visual Studio", confidence: .low)],
            installed: installed
        )
        check(prefix.matches.map(\.bundleId) == ["com.microsoft.VSCode"], "unique prefix matches exactly one app")
        check(prefix.matches.first?.confidence == .low, "confidence is preserved")

        let ambiguous = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Microsoft", confidence: .high)],
            installed: installed
        )
        check(ambiguous.matches.isEmpty, "ambiguous prefix is not a match")
        check(ambiguous.unmatched == ["Microsoft"], "ambiguous prefix is unmatched")

        let typo = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Xcoda", confidence: .high)],
            installed: installed
        )
        check(typo.matches.map(\.bundleId) == ["com.apple.dt.Xcode"], "levenshtein distance 2 matches one app")

        let unknown = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Superhuman", confidence: .high)],
            installed: installed
        )
        check(unknown.matches.isEmpty, "unknown name is dropped")
        check(unknown.unmatched == ["Superhuman"], "unknown name is listed unmatched")

        let hallucinated = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "NotARealApp", confidence: .high)],
            installed: installed
        )
        check(hallucinated.matches.isEmpty, "hallucinated name cannot produce a match")
        check(
            hallucinated.matches.allSatisfy { allowed.contains($0.bundleId) },
            "no match can carry a bundle id outside the whitelist"
        )
        check(
            AppMatcher.firstHit("NotARealApp", in: installed) == nil,
            "firstHit never invents an installed app"
        )

        let reversePrefix = AppMatcher.match(
            names: [AppMatcher.NamedApp(name: "Studio Code", confidence: .high)],
            installed: installed
        )
        check(reversePrefix.matches.isEmpty, "a suffix of an installed name is not a match")
    }

    static func switchPlan() {
        let claude = "com.anthropic.claudefordesktop"
        let figma = "com.figma.Desktop"
        let slack = "com.tinyspeck.slackmacgap"
        let notes = "com.apple.Notes"

        let shared = SwitchPlan.classify(
            outgoing: [claude, figma],
            incoming: [claude, slack],
            keepOpen: []
        )
        check(shared.stay == [claude], "shared apps stay open")
        check(shared.launch == [slack], "incoming-only apps launch")

        let untouched = SwitchPlan.classify(
            outgoing: [figma],
            incoming: [figma],
            keepOpen: []
        )
        check(untouched.stay == [figma], "shared without a destination still stays")

        var work = Profile(name: "Work")
        work.items = [
            .app(bundleId: claude, name: "Claude"),
            .chromeProfile(directory: "Default", displayName: "Work")
        ]
        check(
            SwitchPlan.ownedBundleIds(in: work) == [claude, ChromeService.chromeBundleID],
            "owned ids include apps and Chrome"
        )
    }

    static func terminalStartup() {
        let tabId = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let profileId = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!
        let tabToken = TerminalStartupService.markerToken(tabId: tabId)
        check(tabToken.contains(tabId.uuidString.uppercased()), "tab marker embeds the tab id")
        let tab = TerminalTab(id: tabId, path: "/tmp", command: "npm run dev")
        let title = TerminalStartupService.tabMarkedTitle(roleName: "Iota", tab: tab)
        check(title.contains("Mevin"), "tab title is branded")
        check(title.contains("npm run dev"), "tab title shows the command")
        check(title.contains(tabToken), "tab title embeds the marker")
        let roleToken = TerminalStartupService.roleWindowToken(profileId: profileId)
        check(roleToken.contains(profileId.uuidString.uppercased()), "role window marker embeds profile id")
    }

    static func chromeProfileDetection() {
        check(ChromeService.isLikelyProfileDirectory("Default"), "Default is a profile folder")
        check(ChromeService.isLikelyProfileDirectory("Profile 1"), "Profile 1 is a profile folder")
        check(!ChromeService.isLikelyProfileDirectory("Chrome"), "Chrome is not a profile folder")
        check(!ChromeService.isLikelyProfileDirectory("Random"), "random names are rejected")
        let path = "/Users/me/Library/Application Support/Google/Chrome/Profile 2"
        check(
            ChromeService.profileDirectoryName(fromPasted: "Profile Path: \(path)") == "Profile 2",
            "profile path line is parsed"
        )
        check(
            ChromeProfileOCR.profilePath(from: ["Profile Path", path]) == path,
            "OCR lines yield the profile path"
        )
    }

    static func roleTeardown() {
        let incoming = Set(["com.figma.Desktop", Constants.claudeBundleID])
        let neverClose: Set<String> = [Constants.finderBundleID]
        check(
            RoleTeardown.action(for: Constants.figmaBundleID, incomingOwned: incoming, neverClose: neverClose) == .skip,
            "incoming role apps are skipped during teardown"
        )
        check(
            RoleTeardown.action(for: "com.apple.Music", incomingOwned: incoming, neverClose: neverClose) == .minimize,
            "apps outside the role are minimized"
        )
        check(
            RoleTeardown.action(for: Constants.finderBundleID, incomingOwned: incoming, neverClose: neverClose) == .skip,
            "never-close apps are skipped"
        )
        check(
            RoleTeardown.action(for: Constants.slackBundleID, incomingOwned: incoming, neverClose: neverClose) == .minimize,
            "apps outside the incoming role are minimized (V6)"
        )

        var role = Profile(name: "Work")
        role.items = [
            .app(bundleId: Constants.claudeBundleID, name: "Claude"),
            .chromeProfile(directory: "Default", displayName: "Work")
        ]
        let order = role.roleSurfaceBundleIdsInOrder()
        check(order.first == ChromeService.chromeBundleID, "Chrome is first when that group is first")
    }

    static func slackDestinations() {
        let team = "T012ABCDEF"
        let channel = "C012ABCDEF"

        func ok(_ raw: String, team: String, channel: String?, _ label: String) {
            guard case .success(let parsed) = SlackService.parse(raw) else {
                check(false, label)
                return
            }
            check(parsed.team == team && parsed.channel == channel, label)
        }
        func fail(_ raw: String, _ expected: SlackService.ParseError, _ label: String) {
            guard case .failure(let error) = SlackService.parse(raw) else {
                check(false, label)
                return
            }
            check(error == expected, label)
        }

        ok("slack://open?team=\(team)", team: team, channel: nil, "slack:// workspace")
        ok("slack://channel?team=\(team)&id=\(channel)", team: team, channel: channel, "slack:// channel")
        ok("https://app.slack.com/client/\(team)/\(channel)", team: team, channel: channel, "https client path")
        ok("https://app.slack.com/client/\(team)", team: team, channel: nil, "https workspace path")
        fail("", .empty, "empty slack input is empty")
        fail("https://example.com/client/\(team)", .wrongHost, "a foreign host is refused")
        fail("slack://open", .noTeam, "a slack URL without a team is refused")
        fail("https://acme.slack.com/archives/\(channel)", .noTeam, "a named host without a team id is refused")

        check(
            SlackService.desktopURL(team: team, channel: channel)?.absoluteString
                == "slack://channel?team=\(team)&id=\(channel)",
            "a channel builds slack://channel"
        )
        check(
            SlackService.httpsURL(team: team, channel: nil) == "https://app.slack.com/client/\(team)",
            "a workspace builds the https client URL"
        )

        var item = ProfileItem.app(bundleId: Constants.slackBundleID, name: "Slack")
        item.destination = .slack(team: team, channel: channel)
        check(item.subtitle?.hasPrefix("Opens a Slack channel") == true, "a slack channel reads as a channel")
        check(!(item.subtitle?.contains(team) ?? true), "the team id is never shown")
        check(!(item.subtitle?.contains(channel) ?? true), "the channel id is never shown")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = String(data: try! encoder.encode(item.destination), encoding: .utf8) ?? ""
        check(encoded.contains("\"slack\""), "a slack destination round-trips as slack")
        check(!encoded.lowercased().contains("token"), "no credential-shaped field is encoded")
        let decoded = try? JSONDecoder().decode(ItemDestination.self, from: encoded.data(using: .utf8)!)
        check(decoded == item.destination, "a stored slack destination round-trips")
    }

    static func sessionSnapshots() {
        check(SessionCapture.usedThresholdSeconds == 90, "used threshold is 90 seconds")
        check(SessionCapture.isUsed(90), "90 seconds counts as used")
        check(!SessionCapture.isUsed(15), "15 seconds does not count as used")

        let id = UUID()
        let first = SessionSnapshot(profileId: id, focusSeconds: ["a": 100])
        let second = SessionSnapshot(profileId: id, focusSeconds: ["a": 200])
        let other = SessionSnapshot(profileId: UUID(), focusSeconds: ["b": 100])
        var kept = SessionCapture.retain([], adding: first)
        kept = SessionCapture.retain(kept, adding: other)
        kept = SessionCapture.retain(kept, adding: second)
        let mine = kept.filter { $0.profileId == id }
        check(mine.count == 2, "a second snapshot is kept")
        check(mine.first?.focusSeconds["a"] == 200, "the newest snapshot is first")

        let third = SessionSnapshot(profileId: id, focusSeconds: ["a": 300])
        let fourth = SessionSnapshot(profileId: id, focusSeconds: ["a": 400])
        kept = SessionCapture.retain(kept, adding: third)
        kept = SessionCapture.retain(kept, adding: fourth)
        check(kept.filter { $0.profileId == id }.count == 3, "only three snapshots are kept per profile")
        check(SessionCapture.latest(kept, for: id)?.focusSeconds["a"] == 400, "latest is the newest")

        var item = ProfileItem.app(bundleId: "com.figma.Desktop", name: "Figma")
        item.destination = .figma(kind: .design, fileKey: "ABCDEFGHIJKLMNOPQRSTUV", slug: "Old", nodeId: nil)
        let overlay = SessionSnapshot(
            profileId: id,
            focusSeconds: ["com.figma.Desktop": 120],
            observed: [
                ObservedAppState(
                    bundleId: "com.figma.Desktop",
                    destination: .figma(kind: .design, fileKey: "WXYZabcdefghijklmnopqrst", slug: nil, nodeId: nil),
                    note: nil
                )
            ]
        )
        let used = SessionCapture.overlayDestination(item: item, snapshot: overlay)
        check(
            {
                if case .figma(_, let key, _, _) = used { return key == "WXYZabcdefghijklmnopqrst" }
                return false
            }(),
            "a used snapshot destination overlays the profile"
        )
        let unusedSnap = SessionSnapshot(
            profileId: id,
            focusSeconds: ["com.figma.Desktop": 15],
            observed: overlay.observed
        )
        check(
            SessionCapture.overlayDestination(item: item, snapshot: unusedSnap) == item.destination,
            "an unused snapshot does not overlay the profile"
        )

        check(SessionCapture.looksCredential("sk-abc"), "a key-shaped string is rejected")
        check(SessionCapture.sanitizedNote("Checkout Redesign") == "Checkout Redesign", "a file name is kept")
        check(SessionCapture.sanitizedNote("Bearer tok") == nil, "a credential-shaped note is dropped")

        var profile = Profile(name: "Work")
        profile.items = [.app(bundleId: "com.figma.Desktop", name: "Figma")]
        let extras = SessionCapture.extras(
            usedBundleIds: ["com.figma.Desktop", "com.tinyspeck.slackmacgap", Constants.bundleID],
            profile: profile,
            keepOpen: []
        )
        check(extras == ["com.tinyspeck.slackmacgap"], "extras exclude profile apps and ignored ids")
    }

    static func windowClassifier() {
        let pid: pid_t = 42
        let normal: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: ["Width": 800.0, "Height": 600.0]
        ]
        let overlay: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 25,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: ["Width": 400.0, "Height": 40.0]
        ]
        let tiny: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: ["Width": 50.0, "Height": 50.0]
        ]
        check(WindowClassifier.isNormalWindow(normal), "a standard window counts as normal")
        check(!WindowClassifier.isNormalWindow(overlay), "a high layer overlay is not normal")
        check(!WindowClassifier.isNormalWindow(tiny), "a tiny utility window is not normal")
        check(WindowClassifier.hasNormalWindow(for: pid, in: [normal]), "pid is on screen when a normal window exists")
        check(!WindowClassifier.hasNormalWindow(for: pid, in: [overlay]), "overlay alone does not count as on screen")
        check(!WindowClassifier.hasNormalWindow(for: 99, in: [normal]), "another pid does not match")
    }

    static func chromeLinkValidation() {
        let linked = ProfileItem.chromeProfile(directory: "Profile 2", displayName: "Work")
        let unlinked = ProfileItem.unlinkedChrome()
        check(linked.isChromeLinked, "a profile with a directory is linked")
        check(!unlinked.isChromeLinked, "chrome without a directory is not linked")

        var profile = Profile(name: "Startup")
        profile.items = [unlinked]
        check(profile.includesChrome, "a role with a chrome row includes chrome")
        check(!profile.chromeIsLinked, "chrome row without directory is not linked for launch")

        profile.items = [.app(bundleId: "com.figma.Desktop", name: "Figma")]
        check(!profile.includesChrome, "figma alone does not include chrome")
    }

    static func v6Helpers() {
        check(
            TerminalTabMatcher.commandMatches(configured: "npm run dev", processArgs: "node npm run dev"),
            "terminal command substring match"
        )
        check(
            !TerminalTabMatcher.commandMatches(configured: "npm run dev", processArgs: "python manage.py"),
            "terminal command mismatch is rejected"
        )
        check(ProfileItem.host(of: "https://figma.com/file/abc") == "figma.com", "host extraction for snapshots")

        let snapID = UUID()
        let json = """
        {"profileId":"\(snapID.uuidString)","capturedAt":"2026-01-01T00:00:00Z","focusSeconds":{},"observed":[],"chromeTabURLs":["https://example.com/path"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try? decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
        check(snap?.chromeTabHosts == ["example.com"], "legacy chromeTabURLs migrate to hosts on decode")

        var profile = Profile(name: "Dev")
        profile.items = [
            .app(
                bundleId: Constants.terminalBundleID,
                name: "Terminal",
                terminalTabs: [TerminalTab(path: "/tmp", command: "npm run dev")]
            )
        ]
        let fp = TerminalCommandFingerprint.compute(for: profile)
        check(fp != nil && fp!.count == 64, "terminal fingerprint is SHA256 hex")
        profile.terminalCommandsFingerprint = fp
        check(TerminalCommandFingerprint.matchesStored(profile), "fingerprint matches when stored")

        let key = ChromeWindowService.bindingKey(profileId: profile.id, directory: "Profile 1")
        check(key.contains(profile.id.uuidString.uppercased()), "chrome binding key includes profile id")
    }

    static func v7Stats() {
        let id = UUID()
        let records = [
            RoleUseRecord(
                profileId: id,
                startedAt: Date(timeIntervalSince1970: 0),
                endedAt: Date(timeIntervalSince1970: 3600),
                countedSeconds: 3600
            ),
            RoleUseRecord(
                profileId: id,
                startedAt: Date(timeIntervalSince1970: 7200),
                endedAt: Date(timeIntervalSince1970: 7300),
                countedSeconds: 30
            )
        ]
        let summary = RoleUsageStats.summary(for: id, records: records)
        check(summary.sessionCount == 1, "sub-minute sessions are ignored in stats")
        check(summary.totalSeconds == 3600, "total sums counted sessions only")
        check(RoleUsageStats.formatDuration(seconds: 3660) == "1h 1m", "duration formatting")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        check(RoleUsageStats.formatLastUsed(nil, now: now) == "Not used yet", "never used reads Not used yet")
        check(RoleUsageStats.formatLastUsed(now.addingTimeInterval(-30), now: now) == "Just now", "under a minute reads Just now")
        check(RoleUsageStats.formatLastUsed(now.addingTimeInterval(-12 * 60), now: now) == "12m ago", "minutes ago")
        check(RoleUsageStats.formatLastUsed(now.addingTimeInterval(-4 * 3600), now: now) == "4h ago", "hours ago")
    }

    /// Phase 1 fixes (19 Oct 2026): timer from when set, crash records,
    /// Terminal foreground matching, Chrome launch and window matching.
    static func v9ChromeProfile() {
        typealias B = ChromeWindowService.ToolbarButton
        // Order seen on a real Chrome toolbar (Oct 2026).
        let toolbar = [
            B(role: "AXButton", title: "Back", description: ""),
            B(role: "AXButton", title: "Forward", description: ""),
            B(role: "AXButton", title: "Reload", description: ""),
            B(role: "AXButton", title: "View site information", description: ""),
            B(role: "AXButton", title: "Bookmark this tab", description: ""),
            B(role: "AXButton", title: "Extensions", description: ""),
            B(role: "AXButton", title: "Open Gemini in Chrome", description: ""),
            B(role: "AXButton", title: "Toshit (The Best Man)", description: ""),
            B(role: "AXPopUpButton", title: "Chrome", description: "")
        ]
        check(ChromeWindowService.profileName(fromToolbar: toolbar) == "Toshit (The Best Man)", "profile read from the button before Chrome's menu, not Back")
        var described = toolbar
        described[7] = B(role: "AXButton", title: "", description: "Work")
        check(ChromeWindowService.profileName(fromToolbar: described) == "Work", "profile name read from the description when there is no title")
        check(ChromeWindowService.profileName(fromToolbar: Array(toolbar.dropLast())) == nil, "no Chrome menu button means profile unknown, not guessed")
        var command = toolbar
        command[7] = B(role: "AXButton", title: "Extensions", description: "")
        check(ChromeWindowService.profileName(fromToolbar: command) == nil, "a toolbar command is never taken as a profile")
        check(!ChromeWindowService.isProfileName("Back"), "Back is not a profile name")

        // Reuse only a window showing this role's profile.
        let names = [1: "Personal", 2: "Work"]
        check(ChromeWindowService.decide(windowIds: [1, 2], names: names, wanted: "Work", bound: nil) == .reuse(2), "reuses the window showing the role's profile")
        check(ChromeWindowService.decide(windowIds: [1, 2], names: names, wanted: "Work", bound: 1) == .reuse(2), "a remembered window on another profile is not reused")
        check(ChromeWindowService.decide(windowIds: [1, 2], names: names, wanted: "Work", bound: 2) == .reuse(2), "a remembered window on the right profile is reused")
        check(ChromeWindowService.decide(windowIds: [1, 2], names: [:], wanted: "Work", bound: 1) == .open, "unreadable windows: Chrome opens the profile, never the front window")
        check(ChromeWindowService.decide(windowIds: [1], names: [1: "Back"], wanted: "Back", bound: 1) == .open, "a stored Back name never matches")
        check(ChromeWindowService.decide(windowIds: [1, 2], names: names, wanted: nil, bound: 1) == .open, "unknown profile name: Chrome opens the profile")
        check(ChromeWindowService.pickOpenedWindow(newIds: [5], names: [:], wanted: nil) == 5, "one new window is the profile's window")
        check(ChromeWindowService.pickOpenedWindow(newIds: [5, 6], names: [5: "Personal", 6: "Work"], wanted: "Work") == 6, "several new windows: the one showing the profile")
        check(ChromeWindowService.pickOpenedWindow(newIds: [5, 6], names: [:], wanted: nil) == nil, "several unreadable new windows: none assumed")
        check(ChromeWindowService.pickOpenedWindow(newIds: [], names: [:], wanted: "Work") == nil, "no new window: nothing bound")

        // Cleanup of data from older builds.
        var item = ProfileItem.chromeProfile(directory: "Default", displayName: "Label")
        item.chromeToolbarName = "Back"
        var good = ProfileItem.chromeProfile(directory: "Profile 2", displayName: "Work")
        good.chromeToolbarName = "Work Account"
        var file = StoreFile(
            version: 1,
            profiles: [Profile(name: "A", items: [item]), Profile(name: "B", items: [good])],
            activeSession: nil,
            chromeWindowBindings: [
                "OLD|Default": 1,
                "v2|X|Default": 2,
                ChromeWindowService.bindingKey(profileId: UUID(), directory: "Default"): 3
            ]
        )
        check(JSONProfileStore.clearUnverifiedChromeData(in: &file), "old Chrome data is cleared")
        check(file.chromeWindowBindings.count == 1 && file.chromeWindowBindings.values.first == 3, "only current window bindings survive")
        check(file.profiles[0].items[0].chromeToolbarName == nil, "a stored Back name is cleared")
        check(file.profiles[1].items[0].chromeToolbarName == "Work Account", "a real profile name is kept")
        check(!JSONProfileStore.clearUnverifiedChromeData(in: &file), "cleanup runs once")
    }

    static func chromeDetectAndTitles() {
        typealias W = ChromeWindowService
        check(W.profileName(fromWindowTitle: "About Version - Google Chrome – YC Startup") == "YC Startup", "Chrome: profile name read from the window title")
        check(W.profileName(fromWindowTitle: "New tab - Google Chrome – Toshit (Default)") == "Toshit (Default)", "Chrome: title name with brackets")
        check(W.profileName(fromWindowTitle: "Feed | LinkedIn - Google Chrome") == nil, "Chrome: no suffix (one profile) gives no name")
        check(!W.isProfileName("Hi, Toshit"), "Chrome: the greeting is never a profile name")
        check(!W.isProfileName("Paused"), "Chrome: the sync state is never a profile name")
        check(W.isProfileName("Toshit (Work)"), "Chrome: a real profile name is kept")
        let greeting = [
            W.ToolbarButton(role: "AXButton", title: "Hi, Toshit", description: ""),
            W.ToolbarButton(role: "AXPopUpButton", title: "Chrome", description: "")
        ]
        check(W.profileName(fromToolbar: greeting) == nil, "Chrome: greeting on the profile button is ignored")
        let window = W.ChromeWindow(id: 1, name: "New tab", bounds: CGRect(x: 0, y: 0, width: 10, height: 10), minimized: false)
        check(
            W.matchIndex(for: window, in: [("Other - Google Chrome – A", nil), ("New tab - Google Chrome – B", nil)], excluding: []) == 1,
            "Chrome: Accessibility title with profile suffix matches the AppleScript title"
        )

        let page = ["Executable Path", ":", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                    "Profile Path", ":", "/Users/me/Library/Application Support/Google/Chrome/Profile 4"]
        check(
            ChromeProfileAccessibilityReader.profilePath(fromTexts: page) == "/Users/me/Library/Application Support/Google/Chrome/Profile 4",
            "Detect: path read from the split label / colon / value texts"
        )
        check(
            ChromeProfileAccessibilityReader.profilePath(fromTexts: ["Profile Path: /Users/me/Library/Application Support/Google/Chrome/Default"]) == "/Users/me/Library/Application Support/Google/Chrome/Default",
            "Detect: path read from one combined text"
        )
        check(ChromeProfileAccessibilityReader.profilePath(fromTexts: ["Executable Path", "/Applications/Google Chrome.app"]) == nil, "Detect: no profile path, no guess")

        var file = StoreFile(version: 12, profiles: [
            Profile(name: "Work", items: [ProfileItem(type: .chromeProfile, directory: "Profile 1", chromeToolbarName: "Hi, Toshit")])
        ], activeSession: nil)
        check(JSONProfileStore.clearUnverifiedChromeData(in: &file), "Chrome: a saved greeting is cleared on load")
        check(file.profiles[0].items[0].chromeToolbarName == nil, "Chrome: greeting name removed")
    }

    static func v11() {
        // Change 2: old Chrome profile windows.
        let ids = [10, 11, 12, 13]
        let names = [10: "Work", 11: "Personal", 12: "Work"]
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: names, oldName: "Work", oldBound: nil, newName: "Personal", keep: 11) == [10, 12],
            "V11: every window showing the old profile's name is retired"
        )
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: [:], oldName: "Work", oldBound: 13, newName: "Personal", keep: 11) == [13],
            "V11: Accessibility off, only the window Mevin opened for the old role"
        )
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: [:], oldName: "Work", oldBound: nil, newName: "Personal", keep: nil).isEmpty,
            "V11: unreadable windows Mevin didn't open stay open"
        )
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: [13: "Personal"], oldName: "Work", oldBound: 13, newName: "Personal", keep: nil).isEmpty,
            "V11: a remembered id now showing another profile is left alone"
        )
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: [10: "Me", 11: "Me"], oldName: "Me", oldBound: 10, newName: "Me", keep: 11) == [10],
            "V11: same name in both roles, only the binding counts"
        )
        check(
            ChromeWindowService.oldProfileWindows(windowIds: ids, names: names, oldName: nil, oldBound: nil, newName: "Personal", keep: 11).isEmpty,
            "V11: unknown old name, nothing retired by name"
        )
        check(MevinConfig.chromeOldWindowAction == .minimize, "V11: old Chrome windows minimize until decision 4 shows Chrome asks")

        // Change 4: Apple Music always open.
        check(MevinConfig.defaultNeverCloseBundleIds.contains(Constants.musicBundleID), "V11: Apple Music is on the default Always open list")
        var old = StoreFile(version: 11, profiles: [], activeSession: nil, keepOpenBundleIds: [Constants.finderBundleID])
        check(JSONProfileStore.addMusicToAlwaysOpen(in: &old), "V11: migration adds Music to an existing list")
        check(old.keepOpenBundleIds == [Constants.finderBundleID, Constants.musicBundleID], "V11: Music appended once")
        var removed = StoreFile(version: 12, profiles: [], activeSession: nil, keepOpenBundleIds: [Constants.finderBundleID])
        check(!JSONProfileStore.addMusicToAlwaysOpen(in: &removed), "V11: Music removed by the user stays removed")
        typealias App = KeepOpenPanelHelper.RunningApp
        let music = App(bundleId: Constants.musicBundleID, name: "Music", onScreen: true, frontRank: 0)
        let neverClose: Set<String> = [Constants.musicBundleID]
        let running = [music].filter { !neverClose.contains($0.bundleId) }
        check(KeepOpenPanelHelper.switchRows(running: running, nextRole: []).isEmpty, "V11: Always open Music is never listed")
    }

    static func v10SwitchPanel() {
        typealias App = KeepOpenPanelHelper.RunningApp
        // Role A (Figma, Notes on screen; VLC minimized) to role B (Claude).
        let running = [
            App(bundleId: Constants.claudeBundleID, name: "Claude", onScreen: false),
            App(bundleId: Constants.figmaBundleID, name: "Figma", onScreen: true, frontRank: 2),
            App(bundleId: "org.videolan.vlc", name: "VLC", onScreen: false),
            App(bundleId: Constants.slackBundleID, name: "Slack", onScreen: true, frontRank: 0),
            App(bundleId: "com.apple.Notes", name: "Notes", onScreen: true, frontRank: 1)
        ]
        let roleB: Set<String> = [Constants.claudeBundleID, Constants.slackBundleID]
        let rows = KeepOpenPanelHelper.switchRows(running: running, nextRole: roleB)
        check(rows.map(\.name) == ["Notes", "Figma"], "V10: panel lists on-screen apps outside the next role, front-most first")
        check(!rows.contains { $0.name == "VLC" }, "V10: minimized apps are never listed")
        check(!rows.contains { $0.bundleId == Constants.slackBundleID }, "V10: the next role's own apps are never listed")
        check(
            KeepOpenPanelHelper.switchRows(running: running.filter { !$0.onScreen || roleB.contains($0.bundleId) }, nextRole: roleB).isEmpty,
            "V10: nothing on screen outside the role means no panel"
        )

        check(KeepOpenPanelHelper.primaryLabel(quitCount: 2, starting: false) == "Quit 2 apps and switch", "V10: button says how many apps quit")
        check(KeepOpenPanelHelper.primaryLabel(quitCount: 1, starting: true) == "Quit 1 app and start", "V10: one app, start wording")
        check(KeepOpenPanelHelper.primaryLabel(quitCount: 0, starting: false) == "Switch", "V10: every row ticked says Switch")
        check(KeepOpenPanelHelper.primaryLabel(quitCount: 0, starting: true) == "Start", "V10: every row ticked says Start")

        // Ending.
        let alpha: Set<String> = [Constants.claudeBundleID, Constants.figmaBundleID]
        check(
            KeepOpenPanelHelper.roleApps(running: running, role: alpha) == [Constants.claudeBundleID, Constants.figmaBundleID],
            "V10: Quit role's apps includes minimized role apps, nothing else"
        )
        check(
            KeepOpenPanelHelper.onScreenRows(running: running).map(\.name) == ["Slack", "Notes", "Figma"],
            "V10: Quit all on screen (and the footer) lists only on-screen apps"
        )
    }

    static func phase1Fixes() {
        // Timer counts from when it was set, in awake seconds.
        check(
            SessionClock.remainingSeconds(minutes: 25, setAtAwake: 600, awakeNow: 600) == 1500,
            "a timer set mid-session starts full"
        )
        check(
            SessionClock.remainingSeconds(minutes: 25, setAtAwake: 600, awakeNow: 900) == 1200,
            "a timer counts down from when it was set"
        )
        check(SessionClock.remainingSeconds(minutes: 1, setAtAwake: 0, awakeNow: 500) == 0, "a timer never goes negative")
        check(SessionClock.menuBarLabel(remaining: 1381) == "24m", "menu bar rounds minutes up")
        check(SessionClock.clockText(seconds: 42) == "00:42", "clock under a minute shows seconds")
        check(SessionClock.clockText(seconds: 754) == "12:34", "clock under an hour is mm:ss")
        check(SessionClock.clockText(seconds: 3723) == "1:02:03", "clock from an hour is h:mm:ss")
        check(SessionClock.clockText(seconds: 36_000) == "10:00:00", "clock over ten hours keeps h:mm:ss")

        // A session cut short by a crash is recorded up to its last activity.
        let start = Date(timeIntervalSince1970: 1_000_000)
        var interrupted = ActiveSession(profileId: UUID(), startedAt: start, baselineBundleIds: [])
        check(RoleUsageStats.interruptedRecord(interrupted) == nil, "a crash before any save records nothing")
        interrupted.lastActiveAt = start.addingTimeInterval(1800)
        interrupted.countedSecondsAtLastActive = 1700
        let record = RoleUsageStats.interruptedRecord(interrupted)
        check(record?.endedAt == start.addingTimeInterval(1800), "a crashed session ends at its last activity")
        check(record?.countedSeconds == 1700, "a crashed session keeps its awake seconds")
        interrupted.countedSecondsAtLastActive = 20
        check(RoleUsageStats.interruptedRecord(interrupted) == nil, "a short crashed session is ignored")

        // Terminal: the foreground program, not the shell, is what gets matched.
        let ps = TerminalTabMatcher.parseProcessList("""
          501 Ss   ttys003  login -pf me
          502 S    ttys003  -zsh
          610 S+   ttys003  npm run dev
          611 S+   ttys003  node /Users/me/app/node_modules/.bin/vite
          700 Ss+  ttys004  -zsh
        """)
        check(ps.count == 5, "process list parses")
        let busy = TerminalTabMatcher.foreground(tty: "/dev/ttys003", in: ps)
        check(busy?.pid == 610, "foreground skips the shell")
        check(
            TerminalTabMatcher.commandMatches(configured: "npm run dev", processArgs: busy?.args ?? ""),
            "a hand-started npm run dev is recognised"
        )
        let idle = TerminalTabMatcher.foreground(tty: "ttys004", in: ps)
        check(idle?.pid == 700 && idle?.args == "", "an idle tab has no program")
        check(TerminalTabMatcher.foreground(tty: "ttys009", in: ps) == nil, "an unknown terminal has no foreground")
        let tab = TerminalTab(id: UUID(), path: "/tmp", command: "npm run dev")
        check(
            TerminalStartupService.commandLine(for: tab) == "cd '/tmp' && npm run dev",
            "a tab's command is typed into its own shell"
        )

        // Chrome: no new window flag, links ride with the launch.
        let args = ChromeService.launchArguments(directory: "Profile 2", urls: ["https://a.com", ""])
        check(args == ["--profile-directory=Profile 2", "https://a.com"], "Chrome launch passes profile and links only")
        check(!args.contains("--new-window"), "Chrome launch never asks for an empty new window")

        let windows = ChromeWindowService.parseWindows("12\tfalse\t0\t25\t800\t625\tInbox\n34\ttrue\t100\t100\t900\t700\tDocs\n")
        check(windows.count == 2 && windows[1].minimized, "Chrome windows parse, minimized included")
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Docs", CGRect(x: 100, y: 100, width: 800, height: 600)),
            ("Inbox", CGRect(x: 0, y: 25, width: 800, height: 600))
        ]
        check(
            ChromeWindowService.matchIndex(for: windows[0], in: candidates, excluding: []) == 1,
            "each Chrome window is matched to its own Accessibility window"
        )
        check(ChromeWindowService.bindingKey(profileId: UUID(), directory: "Default").hasPrefix("v3|"), "window bindings are versioned")
    }

    static func chromeToolbarSeedClear() {
        var seeded = ProfileItem.chromeProfile(directory: "Profile 1", displayName: "Work")
        seeded.chromeToolbarName = "Work"
        var real = ProfileItem.chromeProfile(directory: "Profile 2", displayName: "Personal")
        real.chromeToolbarName = "Person 1"
        var file = StoreFile(
            version: 10,
            profiles: [
                Profile(
                    name: "Role",
                    items: [seeded, real],
                    colorId: ProfileColor.navy.rawValue
                )
            ],
            activeSession: nil
        )
        let changed = JSONProfileStore.clearSeededChromeToolbarNames(in: &file)
        check(changed, "seeded toolbar names are cleared on load")
        check(file.profiles[0].items[0].chromeToolbarName == nil, "displayName-as-toolbar is cleared")
        check(file.profiles[0].items[1].chromeToolbarName == "Person 1", "real toolbar name is kept")
    }
}
