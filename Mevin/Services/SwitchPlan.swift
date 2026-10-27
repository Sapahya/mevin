import Foundation

/// Overlap between roles. Teardown is handled by `RoleTeardown`, not quit.
struct SwitchPlan: Equatable {
    /// In both profiles.
    var stay: Set<String>
    /// Incoming-only bundle ids.
    var launch: Set<String>

    static func classify(
        outgoing: Set<String>,
        incoming: Set<String>,
        keepOpen: Set<String>
    ) -> SwitchPlan {
        let stay = outgoing.intersection(incoming)
        let launch = incoming.subtracting(outgoing)
        _ = keepOpen
        return SwitchPlan(stay: stay, launch: launch)
    }

    /// Owned bundle ids a profile is responsible for: apps, Chrome, folder openers.
    static func ownedBundleIds(in profile: Profile) -> Set<String> {
        Set(profile.items.compactMap(\.closeBundleId))
    }
}
