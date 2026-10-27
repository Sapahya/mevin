import AppKit
import CoreGraphics
import Foundation

/// Counts elapsed time excluding sleep and screen lock (PRD V7).
@MainActor
final class AwakeTimeTracker {
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var pausedAt: Date?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    func start(from date: Date = Date()) {
        stopObserving()
        startedAt = date
        accumulated = 0
        pausedAt = nil
        startObserving()
    }

    func stop() -> TimeInterval {
        stopObserving()
        let total = elapsed(now: Date())
        startedAt = nil
        accumulated = 0
        pausedAt = nil
        return total
    }

    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return accumulated }
        // While paused, time stops at the pause; an earlier `now` (a trimmed
        // end at the last activity) still wins.
        let end = pausedAt.map { min($0, now) } ?? now
        return accumulated + max(0, end.timeIntervalSince(startedAt))
    }

    static func secondsSinceLastUserActivity() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pause()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        })
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.pause()
        })
        distributedObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        })
    }

    private func stopObserving() {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers = []
        for token in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedObservers = []
    }

    private func pause() {
        guard pausedAt == nil, let start = startedAt else { return }
        pausedAt = Date()
        accumulated += max(0, pausedAt!.timeIntervalSince(start))
        startedAt = pausedAt
    }

    private func resume() {
        guard pausedAt != nil else { return }
        startedAt = Date()
        pausedAt = nil
    }
}
