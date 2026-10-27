import AppKit
import Foundation

/// Clears apps by minimizing windows, never quitting (PRD V6, V9).
enum RoleTeardown {
    enum Action: Equatable {
        case skip
        case minimize
    }

    static func action(
        for bundleId: String,
        incomingOwned: Set<String>,
        neverClose: Set<String>,
        keep: Set<String> = []
    ) -> Action {
        if neverClose.contains(bundleId) || Constants.ignoredBundleIDs.contains(bundleId) {
            return .skip
        }
        if keep.contains(bundleId) {
            return .skip
        }
        if incomingOwned.contains(bundleId) {
            return .skip
        }
        return .minimize
    }

    /// Minimizes exactly these apps (the panel's unticked rows), never the
    /// Always open list or the apps Mevin ignores (PRD V9).
    @MainActor
    static func minimize(_ bundleIds: Set<String>, neverClose: Set<String>) -> Set<String> {
        let targets = bundleIds.filter {
            action(for: $0, incomingOwned: [], neverClose: neverClose) == .minimize
        }
        return WindowService.minimizeWindows(bundleIds: targets)
    }
}
