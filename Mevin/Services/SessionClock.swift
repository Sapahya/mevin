import Foundation

/// Pure timer and clock arithmetic for the active session (PRD V7 Change 5,
/// V8 Change 6). All times are awake seconds: sleep and lock are excluded.
enum SessionClock {
    /// Seconds left on a timer set `setAtAwake` seconds into the session.
    static func remainingSeconds(minutes: Int, setAtAwake: TimeInterval, awakeNow: TimeInterval) -> TimeInterval {
        max(0, TimeInterval(minutes * 60) - max(0, awakeNow - setAtAwake))
    }

    /// Menu bar label, rounded up to whole minutes ("23m").
    static func menuBarLabel(remaining: TimeInterval) -> String {
        "\(Int(ceil(remaining / 60)))m"
    }

    /// `mm:ss` under an hour, `h:mm:ss` from one hour.
    static func clockText(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
