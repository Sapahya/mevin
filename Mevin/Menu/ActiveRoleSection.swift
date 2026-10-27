import SwiftUI

/// The active role, out of the list, sitting directly on the tinted panel
/// (PRD V8 Change 6): name, live clock, Edit, and End session. Clicking the
/// clock swaps End session for the timer chooser.
struct ActiveRoleSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: Profile

    @State private var timerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.activeGap) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: SessionCardStyles.activeGap) {
                    Text(profile.name)
                        .sessionCardFont(.title)
                        .foregroundStyle(SessionCardStyles.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button {
                        timerOpen.toggle()
                    } label: {
                        Text(model.activeClockText)
                            .sessionCardFont(.clock)
                            .foregroundStyle(SessionCardStyles.textPrimary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Timer options")
                    .accessibilityLabel(model.activeTimerMinutes == nil ? "Session time" : "Time left")
                    .accessibilityValue(model.activeClockText)
                    .accessibilityHint("Timer options")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MevinIconButton(symbol: "pencil", label: "Edit \(profile.name)") {
                    model.editProfile(id: profile.id)
                }
            }
            .frame(height: SessionCardStyles.activeTopRowHeight)

            if timerOpen {
                SessionCardTimerChooser(
                    mode: .active,
                    height: SessionCardStyles.endBarHeight,
                    fill: SessionCardStyles.endBarFill
                ) {
                    timerOpen = false
                }
            } else {
                endBar
            }
        }
        .padding(.vertical, SessionCardStyles.activePaddingV)
        .padding(.horizontal, SessionCardStyles.activePaddingH)
        .animation(reduceMotion ? nil : .easeInOut(duration: SessionCardStyles.expandAnimation), value: timerOpen)
    }

    private var endBar: some View {
        Button {
            model.beginEndFlow()
        } label: {
            HStack(spacing: SessionCardStyles.startLabelGap) {
                Image(systemName: "stop.fill")
                    .font(.system(size: SessionCardStyles.startIconSize))
                Text("End session")
                    .sessionCardFont(.button)
            }
            .foregroundStyle(SessionCardStyles.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: SessionCardStyles.endBarHeight)
            .background(SessionCardStyles.endBarFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End session, \(profile.name)")
    }
}
