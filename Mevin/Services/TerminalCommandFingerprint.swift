import CryptoKit
import Foundation

enum TerminalCommandFingerprint {
    static func compute(for profile: Profile) -> String? {
        guard let item = profile.terminalTabsItem(),
              let tabs = item.terminalTabs,
              !tabs.isEmpty
        else { return nil }

        let parts = tabs.map { tab -> String in
            let path = ProfileItem.effectiveTerminalPath(for: tab)
            let cmd = TerminalTabMatcher.normalizedCommand(tab.trimmedCommand)
            return "\(path)|\(cmd)"
        }.sorted()

        let data = Data(parts.joined(separator: "\n").utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func matchesStored(_ profile: Profile) -> Bool {
        guard let stored = profile.terminalCommandsFingerprint else { return true }
        guard let current = compute(for: profile) else { return true }
        return stored == current
    }
}
