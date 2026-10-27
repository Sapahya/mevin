import SwiftUI

/// Shared V8 building blocks (PRD V8 Changes 3, 9 and section 11): capsule
/// actions, round icon buttons, chips, rows and screen headers. Every value
/// comes from `SessionCardStyles`.

/// Capsule action. Prominent = black 60% (like the Start bar); plain = white 10%.
struct MevinCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var destructive: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sessionCardFont(.button)
            .foregroundStyle(destructive ? SessionCardStyles.destructive : SessionCardStyles.textPrimary)
            .padding(.horizontal, SessionCardStyles.chipPaddingH + 4)
            .frame(maxWidth: .infinity, minHeight: SessionCardStyles.endBarHeight)
            .background(
                prominent ? SessionCardStyles.startBarFill : SessionCardStyles.chipFill,
                in: Capsule()
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

/// Small pill-shaped text button (white 10%, hover white 20%), e.g. "Add Profile" style chips.
struct MevinChipButtonStyle: ButtonStyle {
    var selected: Bool = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.mevinCompactChips) private var compact

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sessionCardFont(.chip)
            .foregroundStyle(SessionCardStyles.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, SessionCardStyles.chipPaddingV)
            .padding(.horizontal, compact ? SessionCardStyles.chipPaddingHCompact : SessionCardStyles.chipPaddingH)
            .frame(height: SessionCardStyles.chipHeight)
            .background(
                (selected || hovering || configuration.isPressed)
                    ? SessionCardStyles.chipHoverFill
                    : SessionCardStyles.chipFill,
                in: RoundedRectangle(cornerRadius: SessionCardStyles.chipRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: SessionCardStyles.chipRadius))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}

/// Round icon-only button, 28 × 28 (Change 9 minimum target).
struct MevinIconButton: View {
    let symbol: String
    let label: String
    var fill: Color = SessionCardStyles.iconButtonFill
    var iconOpacity: Double = SessionCardStyles.valueOpacity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: SessionCardStyles.iconButtonIconSize, weight: .regular))
                .foregroundStyle(SessionCardStyles.textPrimary.opacity(iconOpacity))
                .frame(width: SessionCardStyles.iconButtonSize, height: SessionCardStyles.iconButtonSize)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Header for screens other than the list: back button, title.
struct MevinScreenHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: SessionCardStyles.headerButtonGap) {
            MevinIconButton(symbol: "chevron.left", label: "Back", fill: SessionCardStyles.roundButtonFill, action: back)
            Text(title)
                .sessionCardFont(.headerTitle)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(minHeight: SessionCardStyles.headerHeight)
    }
}

/// Secondary text with the V8 contrast rules (0.7, or 0.9 with Increase contrast).
struct MevinSecondaryText: View {
    let text: String
    var style: SessionCardStyles.FontStyle = .body
    var opacity: Double = SessionCardStyles.secondaryOpacity
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ text: String, style: SessionCardStyles.FontStyle = .body, opacity: Double = SessionCardStyles.secondaryOpacity) {
        self.text = text
        self.style = style
        self.opacity = opacity
    }

    var body: some View {
        Text(text)
            .sessionCardFont(style)
            .foregroundStyle(
                SessionCardStyles.textPrimary.opacity(
                    SessionCardStyles.opacity(opacity, increasedContrast: contrast == .increased)
                )
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// A 10 pt rounded row surface (section 11).
    func mevinRow(fill: Color = SessionCardStyles.rowFill) -> some View {
        padding(.vertical, SessionCardStyles.rowPaddingV)
            .padding(.horizontal, SessionCardStyles.rowPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))
    }

    /// Text field surface used across the editor and settings.
    func mevinField() -> some View {
        textFieldStyle(.plain)
            .sessionCardFont(.body)
            .padding(.horizontal, SessionCardStyles.rowPaddingH)
            .frame(minHeight: SessionCardStyles.smallButtonHeight)
            .background(SessionCardStyles.fieldFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.fieldRadius))
    }
}
