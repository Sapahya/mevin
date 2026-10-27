import SwiftUI

/// Start bar on an expanded card (PRD V8 Change 5): play + "Start session"
/// (or "Switch session" while another role is active), chevron for the timer.
struct SessionCardStartBar: View {
    let label: String
    let profileName: String
    let onStart: () -> Void
    let onChevron: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onStart) {
                HStack(spacing: SessionCardStyles.startLabelGap) {
                    Image(systemName: "play.fill")
                        .font(.system(size: SessionCardStyles.startIconSize))
                    Text(label)
                        .sessionCardFont(.button)
                        .lineLimit(1)
                }
                .foregroundStyle(SessionCardStyles.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(profileName)")

            MevinIconButton(
                symbol: "chevron.down",
                label: "Timer options",
                fill: SessionCardStyles.roundButtonFill,
                iconOpacity: 1,
                action: onChevron
            )
        }
        .padding(SessionCardStyles.startBarPadding)
        .frame(maxWidth: .infinity)
        .frame(height: SessionCardStyles.startBarHeight)
        .background(SessionCardStyles.startBarFill, in: Capsule())
    }
}

/// Timer chooser capsule (PRD V8 Changes 5 and 6). On a card, a chip starts
/// the session with that timer; in the active section it only sets the timer
/// and adds "No timer".
struct SessionCardTimerChooser: View {
    enum Mode: Equatable {
        case start(profileID: UUID)
        case active
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast
    let mode: Mode
    var height: CGFloat = SessionCardStyles.startBarHeight
    var fill: Color = SessionCardStyles.startBarFill
    let onBack: () -> Void

    @State private var enteringCustom = false
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    private static let presets = [25, 50, 90]

    var body: some View {
        Group {
            if enteringCustom {
                customRow
            } else {
                // The active section adds a fifth chip; drop the label, then
                // tighten chip padding, rather than overflow the 310 capsule.
                ViewThatFits(in: .horizontal) {
                    chipsRow(showLabel: true, compact: false)
                    chipsRow(showLabel: false, compact: false)
                    chipsRow(showLabel: false, compact: true)
                }
            }
        }
        .padding(.horizontal, SessionCardStyles.startBarPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(fill, in: Capsule())
    }

    private func chipsRow(showLabel: Bool, compact: Bool) -> some View {
        HStack(spacing: SessionCardStyles.startLabelGap) {
            backButton { onBack() }
            if showLabel {
                Text("Timer")
                    .sessionCardFont(.timerLabel)
                    .foregroundStyle(SessionCardStyles.textPrimary.opacity(
                        SessionCardStyles.opacity(SessionCardStyles.timerLabelOpacity, increasedContrast: contrast == .increased)
                    ))
                    .fixedSize()
            }
            HStack(spacing: SessionCardStyles.chipGap) {
                ForEach(Self.presets, id: \.self) { minutes in
                    chip("\(minutes)m", compact: compact, selected: isCurrent(minutes)) { choose(minutes) }
                }
                chip("Custom", compact: compact, selected: false) {
                    customText = ""
                    enteringCustom = true
                    customFocused = true
                }
                if mode == .active {
                    chip("No timer", compact: compact, selected: model.activeTimerMinutes == nil) { choose(nil) }
                }
            }
            .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var customRow: some View {
        HStack(spacing: SessionCardStyles.startLabelGap) {
            backButton { enteringCustom = false }
            TextField("", text: $customText, prompt: Text("1 to 600"))
                .mevinField()
                .frame(width: SessionCardStyles.customFieldWidth + 30)
                .focused($customFocused)
                .onSubmit(submitCustom)
                .accessibilityLabel("Minutes")
            Text("min")
                .sessionCardFont(.chip)
                .foregroundStyle(SessionCardStyles.textPrimary.opacity(SessionCardStyles.valueOpacity))
            Spacer(minLength: 0)
            Button(mode == .active ? "Set" : "Start", action: submitCustom)
                .buttonStyle(MevinChipButtonStyle())
                .disabled(customMinutes == nil)
        }
    }

    private var customMinutes: Int? {
        guard let value = Int(customText.trimmingCharacters(in: .whitespaces)),
              SessionCardStyles.customMinutesRange.contains(value)
        else { return nil }
        return value
    }

    private func submitCustom() {
        guard let minutes = customMinutes else { return }
        enteringCustom = false
        choose(minutes)
    }

    private func isCurrent(_ minutes: Int) -> Bool {
        mode == .active && model.activeTimerMinutes == minutes
    }

    private func choose(_ minutes: Int?) {
        switch mode {
        case .start(let profileID):
            guard let minutes else { return }
            model.startSession(profileID: profileID, timerMinutes: minutes)
        case .active:
            if let minutes {
                model.timerRepeatPrefillMinutes = minutes
            }
            model.setActiveTimer(minutes: minutes)
            onBack()
        }
    }

    private func chip(_ title: String, compact: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MevinChipButtonStyle(selected: selected))
            .environment(\.mevinCompactChips, compact)
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        MevinIconButton(
            symbol: "chevron.left",
            label: "Back",
            fill: SessionCardStyles.roundButtonFill,
            iconOpacity: 1,
            action: action
        )
    }
}

private struct MevinCompactChipsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Tighter chip padding when five chips must share one capsule.
    var mevinCompactChips: Bool {
        get { self[MevinCompactChipsKey.self] }
        set { self[MevinCompactChipsKey.self] = newValue }
    }
}
