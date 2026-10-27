import AppKit
import SwiftUI

/// One profile card (PRD V8 Changes 4, 5, 8). Solid profile colour, no border
/// in any state. Default 60 tall; clicked, it expands to 118 with a Start bar.
struct ProfileCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let profile: Profile
    /// Keyboard highlight; looks the same as hover.
    let isHighlighted: Bool
    let onHover: (Bool) -> Void

    @State private var isHovered = false
    @State private var timerOpen = false

    private var isExpanded: Bool { model.isExpanded(profile.id) }

    private var surfaceState: SessionCardSurfaceState {
        (isHovered || isHighlighted || isExpanded) ? .elevated : .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.cardRowGap) {
            headerRow
            if isExpanded {
                if timerOpen {
                    SessionCardTimerChooser(mode: .start(profileID: profile.id)) {
                        timerOpen = false
                    }
                } else {
                    SessionCardStartBar(
                        label: startLabel,
                        profileName: profile.name,
                        onStart: { model.startOrEndSession(profileID: profile.id) },
                        onChevron: { timerOpen = true }
                    )
                }
            }
        }
        .padding(.vertical, SessionCardStyles.cardPaddingV)
        .padding(.horizontal, SessionCardStyles.cardPaddingH)
        .frame(
            maxWidth: .infinity,
            minHeight: isExpanded ? SessionCardStyles.cardExpandedHeight : SessionCardStyles.cardHeight,
            alignment: .top
        )
        .background {
            SessionCardPalette.cardBackground(color: profile.color, state: surfaceState)
        }
        .clipShape(RoundedRectangle(cornerRadius: SessionCardStyles.cardRadius))
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: SessionCardStyles.expandAnimation), value: isExpanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: SessionCardStyles.expandAnimation), value: timerOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: SessionCardStyles.hoverAnimation), value: surfaceState)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { timerOpen = false }
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: SessionCardStyles.cardRowGap) {
            VStack(alignment: .leading, spacing: SessionCardStyles.cardColumnGap) {
                Text(profile.name)
                    .sessionCardFont(.title)
                    .foregroundStyle(SessionCardStyles.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                lastUsedPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MevinIconButton(symbol: "pencil", label: "Edit \(profile.name)") {
                model.editProfile(id: profile.id)
            }
        }
        // Click toggles; the second click of a double-click starts the role.
        .contentShape(Rectangle())
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 {
                model.startOrEndSession(profileID: profile.id)
            } else {
                model.cardTapped(profileID: profile.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Collapse" : "Show Start session")
    }

    private var lastUsedPill: some View {
        HStack(spacing: SessionCardStyles.pillGap) {
            HStack(spacing: SessionCardStyles.pillInnerGap) {
                Image(systemName: "hourglass")
                    .font(.system(size: SessionCardStyles.pillIconSize))
                Text("Last used")
                    .sessionCardFont(.pill)
            }
            .opacity(secondary(SessionCardStyles.pillLabelOpacity))
            Text(lastUsedValue)
                .sessionCardFont(.pill)
                .opacity(secondary(SessionCardStyles.valueOpacity))
        }
        .foregroundStyle(SessionCardStyles.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, SessionCardStyles.pillPadding)
        .frame(height: SessionCardStyles.pillHeight)
        .background(SessionCardStyles.pillFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.pillRadius))
        .fixedSize()
    }

    private var lastUsedValue: String {
        _ = model.now
        let summary = model.usageSummary(for: profile.id)
        return RoleUsageStats.formatLastUsed(summary.lastUsed, now: Date())
    }

    private var startLabel: String {
        let base = model.activeSession == nil ? "Start session" : "Switch session"
        if let minutes = profile.defaultTimerMinutes, minutes > 0 {
            return "\(base) · \(minutes)m"
        }
        return base
    }

    private func secondary(_ base: Double) -> Double {
        SessionCardStyles.opacity(base, increasedContrast: contrast == .increased)
    }
}
