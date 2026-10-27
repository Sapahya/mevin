import Foundation

/// Quiet capture helpers. Thresholds live here so a tune is one edit.
enum SessionCapture {
    static let usedThresholdSeconds = 90
    static let maxSnapshotsPerProfile = 3
    static let maxChromeTabs = 8
    static let timerInterval: TimeInterval = 60

    static func isUsed(_ seconds: Int) -> Bool {
        seconds >= usedThresholdSeconds
    }

    static func retain(_ snapshots: [SessionSnapshot], adding new: SessionSnapshot) -> [SessionSnapshot] {
        let others = snapshots.filter { $0.profileId != new.profileId }
        let mine = [new] + snapshots.filter { $0.profileId == new.profileId }
        return Array(mine.prefix(maxSnapshotsPerProfile)) + others
    }

    static func latest(_ snapshots: [SessionSnapshot], for profileId: UUID) -> SessionSnapshot? {
        snapshots.first { $0.profileId == profileId }
    }

    /// Snapshot destination if the app was actually used and we parsed a real
    /// one; otherwise the profile's own destination. Never invents.
    static func overlayDestination(item: ProfileItem, snapshot: SessionSnapshot?) -> ItemDestination? {
        guard let bundleId = item.bundleId, let snapshot else { return item.destination }
        let seconds = snapshot.focusSeconds[bundleId] ?? 0
        guard isUsed(seconds) else { return item.destination }
        if let observed = snapshot.observed.first(where: { $0.bundleId == bundleId })?.destination {
            return observed
        }
        return item.destination
    }

    static func looksCredential(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        if text.count > 160 { return true }
        let lower = text.lowercased()
        let banned = ["token", "cookie", "secret", "password", "authorization", "bearer ", "sk-"]
        return banned.contains { lower.contains($0) }
    }

    static func sanitizedNote(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksCredential(trimmed) else { return nil }
        return trimmed
    }

    static func extras(
        usedBundleIds: Set<String>,
        profile: Profile,
        keepOpen: Set<String>,
        carriedOver: Set<String> = []
    ) -> Set<String> {
        let owned = SwitchPlan.ownedBundleIds(in: profile)
        return usedBundleIds
            .subtracting(owned)
            .subtracting(keepOpen)
            .subtracting(carriedOver)
            .subtracting(Constants.ignoredBundleIDs)
    }
}
