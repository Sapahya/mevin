import Foundation

struct JSONProfileStore {
    /// 1: the original, with handoff notes and the old item spellings.
    /// 2: notes dropped, kinds renamed. Shipped without colours.
    /// 3: adds profile colours, app destinations and the Keep open list.
    /// 4: Claude destinations open in the desktop app rather than a Chrome tab.
    /// 5: Claude destinations store project UUIDs, not full URLs.
    /// 6: session snapshots sit beside profiles.
    /// 7: optional startupCommand on folder items (Terminal run on start).
    /// 8: Terminal tabs on the Terminal app row; folder Terminal opener removed.
    /// 9: Application Support data path; snapshot hosts; Chrome window bindings.
    /// 10: role usage stats, check-in interval, default session timer on profiles.
    /// 12: Apple Music added to the Always open list once (V11 Change 4).
    static let currentVersion = 12

    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultStoreURL()
        }
    }

    static func defaultStoreURL() -> URL {
        migrateDocumentsStoreIfNeeded()
        return MevinConfig.storeFileURL
    }

    /// One-time move from ~/Documents/Mevin to Application Support (PRD V6).
    private static func migrateDocumentsStoreIfNeeded() {
        let fm = FileManager.default
        let newURL = MevinConfig.storeFileURL
        let newFolder = newURL.deletingLastPathComponent()
        if fm.fileExists(atPath: newURL.path) { return }

        var legacy = MevinConfig.legacyDocumentsStoreURL
        if !fm.fileExists(atPath: legacy.path) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
            legacy = docs
                .appendingPathComponent(MevinConfig.legacyDataFolderName, isDirectory: true)
                .appendingPathComponent(MevinConfig.storeFileName)
        }
        guard fm.fileExists(atPath: legacy.path) else { return }

        try? fm.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try? fm.copyItem(at: legacy, to: newURL)

        let bak = legacy.deletingLastPathComponent().appendingPathComponent("profiles.json.bak")
        if !fm.fileExists(atPath: bak.path) {
            try? fm.copyItem(at: legacy, to: bak)
        }
    }

    func load() throws -> StoreFile {
        let fm = FileManager.default
        try createFolderIfNeeded()

        if !fm.fileExists(atPath: fileURL.path) {
            let empty = StoreFile(version: Self.currentVersion, profiles: [], activeSession: nil)
            try save(empty)
            return empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var file = try decoder.decode(StoreFile.self, from: data)

        let needsRewrite = file.version < Self.currentVersion
        let migratedColours = Self.migratePreV8Colours(in: &file)
        Self.assignMissingColours(to: &file)
        let migratedTerminal = Self.migrateV5Terminal(to: &file)
        let clearedToolbar = Self.clearSeededChromeToolbarNames(in: &file)
        let clearedChrome = Self.clearUnverifiedChromeData(in: &file)
        let addedMusic = Self.addMusicToAlwaysOpen(in: &file)
        if needsRewrite || migratedTerminal || clearedToolbar || clearedChrome || migratedColours || addedMusic
            || file.version < Self.currentVersion {
            file.version = Self.currentVersion
            try save(file)
        }

        return file
    }

    /// Files written before version 12 get Apple Music on their Always open
    /// list, once. Removing it afterwards sticks, since the version moves on.
    /// An empty list is left empty: the app fills it with the defaults.
    @discardableResult
    static func addMusicToAlwaysOpen(in file: inout StoreFile) -> Bool {
        guard file.version < 12,
              !file.keepOpenBundleIds.isEmpty,
              !file.keepOpenBundleIds.contains(Constants.musicBundleID)
        else { return false }
        file.keepOpenBundleIds.append(Constants.musicBundleID)
        return true
    }

    /// Older builds seeded `chromeToolbarName` from the Mevin display label, which
    /// breaks window matching. Clear those so AX capture can fill the real name.
    @discardableResult
    static func clearSeededChromeToolbarNames(in file: inout StoreFile) -> Bool {
        var changed = false
        for profileIndex in file.profiles.indices {
            for itemIndex in file.profiles[profileIndex].items.indices {
                let item = file.profiles[profileIndex].items[itemIndex]
                guard item.type == .chromeProfile,
                      let toolbar = item.chromeToolbarName,
                      let display = item.displayName,
                      toolbar.localizedCaseInsensitiveCompare(display) == .orderedSame
                else { continue }
                file.profiles[profileIndex].items[itemIndex].chromeToolbarName = nil
                changed = true
            }
        }
        return changed
    }

    /// Older builds read Chrome's Back button as the profile name and could bind
    /// a role to another profile's window (PRD V9 Change 5). Drops window
    /// bindings from those builds and any stored name that is a toolbar command.
    @discardableResult
    static func clearUnverifiedChromeData(in file: inout StoreFile) -> Bool {
        var changed = false
        let current = file.chromeWindowBindings.filter { ChromeWindowService.isCurrentBindingKey($0.key) }
        if current.count != file.chromeWindowBindings.count {
            file.chromeWindowBindings = current
            changed = true
        }
        for profileIndex in file.profiles.indices {
            for itemIndex in file.profiles[profileIndex].items.indices {
                let item = file.profiles[profileIndex].items[itemIndex]
                guard item.type == .chromeProfile,
                      let toolbar = item.chromeToolbarName,
                      !ChromeWindowService.isProfileName(toolbar)
                else { continue }
                file.profiles[profileIndex].items[itemIndex].chromeToolbarName = nil
                changed = true
            }
        }
        return changed
    }

    /// Every profile needs a colour, and files written before version 3 have
    /// none. Assigning by palette order keeps existing profiles visually distinct
    /// rather than making them all the same colour.
    /// V4 folder + Terminal opener → Terminal app tabs (PRD V5).
    @discardableResult
    static func migrateV5Terminal(to file: inout StoreFile) -> Bool {
        var changed = false
        for index in file.profiles.indices {
            var profile = file.profiles[index]
            let terminalFolders = profile.items.filter {
                $0.type == .folder && $0.appBundleId == Constants.terminalBundleID
            }

            if !terminalFolders.isEmpty {
                changed = true
                var terminalIndex = profile.items.firstIndex {
                    $0.type == .app && $0.bundleId == Constants.terminalBundleID
                }
                if terminalIndex == nil {
                    profile.items.append(.app(bundleId: Constants.terminalBundleID, name: "Terminal"))
                    terminalIndex = profile.items.count - 1
                }
                if let terminalIndex {
                    var tabs = profile.items[terminalIndex].terminalTabs ?? []
                    for folder in terminalFolders {
                        tabs.append(
                            TerminalTab(
                                id: folder.id,
                                path: folder.path,
                                command: folder.startupCommand
                            )
                        )
                    }
                    profile.items[terminalIndex].terminalTabs = tabs
                }
                profile.items.removeAll {
                    $0.type == .folder && $0.appBundleId == Constants.terminalBundleID
                }
            }

            for itemIndex in profile.items.indices where profile.items[itemIndex].type == .folder {
                profile.items[itemIndex].startupCommand = nil
            }
            file.profiles[index] = profile
        }
        return changed
    }

    /// V8 replaced the palette. Stored pre-V8 colour ids are rewritten to
    /// their replacement (indigo → navy, teal → slate, bronze → bronze,
    /// clay → wine, violet → plum, forest → rose); unknown ids are left alone.
    @discardableResult
    static func migratePreV8Colours(in file: inout StoreFile) -> Bool {
        var changed = false
        for index in file.profiles.indices {
            let id = file.profiles[index].colorId
            guard ProfileColor(rawValue: id) == nil, let replacement = ProfileColor.legacyIDs[id] else { continue }
            file.profiles[index].colorId = replacement.rawValue
            changed = true
        }
        return changed
    }

    static func assignMissingColours(to file: inout StoreFile) {
        var taken = Set(file.profiles.map(\.colorId).filter { !$0.isEmpty })
        let palette = ProfileColor.allCases

        for index in file.profiles.indices where file.profiles[index].colorId.isEmpty {
            let next = palette.first { !taken.contains($0.rawValue) }
                ?? palette[index % palette.count]
            file.profiles[index].colorId = next.rawValue
            taken.insert(next.rawValue)
        }
    }

    func save(_ store: StoreFile) throws {
        try createFolderIfNeeded()

        var outgoing = store
        outgoing.version = Self.currentVersion

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(outgoing)

        let temp = fileURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            _ = try fm.replaceItemAt(fileURL, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: fileURL)
        }
    }

    private func createFolderIfNeeded() throws {
        let fm = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}
