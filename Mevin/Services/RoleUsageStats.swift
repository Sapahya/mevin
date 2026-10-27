import Foundation

struct RoleUseRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var profileId: UUID
    var startedAt: Date
    var endedAt: Date
    var countedSeconds: Int

    init(
        id: UUID = UUID(),
        profileId: UUID,
        startedAt: Date,
        endedAt: Date,
        countedSeconds: Int
    ) {
        self.id = id
        self.profileId = profileId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.countedSeconds = countedSeconds
    }
}

enum RoleUsageStats {
    static let minimumCountedSeconds = 60

    /// A session still on file at launch was cut short (crash, force quit,
    /// shutdown). It counts up to its last recorded activity, or not at all
    /// if nothing was recorded yet.
    static func interruptedRecord(_ session: ActiveSession) -> RoleUseRecord? {
        guard let end = session.lastActiveAt,
              let counted = session.countedSecondsAtLastActive,
              counted >= minimumCountedSeconds
        else { return nil }
        return RoleUseRecord(
            profileId: session.profileId,
            startedAt: session.startedAt,
            endedAt: max(end, session.startedAt),
            countedSeconds: counted
        )
    }

    struct Summary: Equatable {
        var lastUsed: Date?
        var totalSeconds: Int
        var sessionCount: Int

        var averageSeconds: Int {
            guard sessionCount > 0 else { return 0 }
            return totalSeconds / sessionCount
        }
    }

    static func summary(for profileId: UUID, records: [RoleUseRecord]) -> Summary {
        let mine = records.filter { $0.profileId == profileId && $0.countedSeconds >= minimumCountedSeconds }
        let total = mine.reduce(0) { $0 + $1.countedSeconds }
        let last = mine.map(\.endedAt).max()
        return Summary(lastUsed: last, totalSeconds: total, sessionCount: mine.count)
    }

    static func mostUsedProfileId(in records: [RoleUseRecord], profiles: [Profile]) -> UUID? {
        var totals: [UUID: Int] = [:]
        for record in records where record.countedSeconds >= minimumCountedSeconds {
            totals[record.profileId, default: 0] += record.countedSeconds
        }
        guard let maxValue = totals.values.max(), maxValue > 0 else { return nil }
        let leaders = Set(totals.filter { $0.value == maxValue }.map(\.key))
        return profiles.first { leaders.contains($0.id) }?.id
    }

    static func formatLastUsed(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not used yet" }
        let seconds = now.timeIntervalSince(date)
        // PRD V8 Change 4: "Just now" under a minute, then minutes, hours,
        // "Yesterday", then a date ("3 Oct").
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func formatDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
