import Foundation

/// PRD §8 usage thresholds and §7 app lists. Tune here after real use.
enum UsageThresholds {
    static let idleCutoffSeconds = 5 * 60
    static let activeTimeSeconds = 5 * 60
    static let switchInCount = 5
    static let switchInMinimumSeconds = 10
    static let interactionCount = 50
    static let visibleTimeSeconds = 30 * 60
    static let playingTimeSeconds = 30 * 60
    static let qualifyingRoleUseSeconds = 15 * 60
    static let savePointIntervalSeconds = 15 * 60
}

enum MevinConfig {
    static let dataFolderName = "Mevin"
    static let storeFileName = "profiles.json"
    static let legacyDataFolderName = "MAAL"
    static let legacyDocumentsFolderName = "Mevin"

    /// What happens to the old role's Chrome profile windows on a switch (PRD
    /// V10 decision 4, V11 Change 2): closed if Chrome asks "Leave site?" on a
    /// scripted close, minimized if it doesn't. Minimize until the test on the
    /// owner's Mac shows Chrome asks.
    static let chromeOldWindowAction: ChromeWindowService.OldWindowAction = .minimize

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(dataFolderName, isDirectory: true)
    }

    static var storeFileURL: URL {
        applicationSupportDirectory.appendingPathComponent(storeFileName)
    }

    static var legacyDocumentsStoreURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs
            .appendingPathComponent(legacyDocumentsFolderName, isDirectory: true)
            .appendingPathComponent(storeFileName)
    }

    /// PRD §11: ships with Finder and Mevin on the never-close list; V11
    /// Change 4 adds Apple Music.
    static var defaultNeverCloseBundleIds: [String] {
        [Constants.finderBundleID, Constants.bundleID, Constants.musicBundleID]
    }

}
