import SwiftUI

/// V8 design tokens (PRD `mevin-prd-v8.md`, checked against
/// `docs/design/figma-export-v2-latest.css.txt`; the PRD wins).
/// Views read every size, colour and opacity from here.
enum SessionCardStyles {
    // MARK: - Panel (Change 1, 2, 3)

    static let panelWidth: CGFloat = 350
    /// Menu bar M, height in points (width follows the artwork).
    static let menuBarIconHeight: CGFloat = 18
    static let panelPadding: CGFloat = 10
    static let panelRadius: CGFloat = 12
    static let contentWidth: CGFloat = 330
    static let sectionGapIdle: CGFloat = 10
    static let sectionGapActive: CGFloat = 12

    /// Black 40% over the glass, for white-text legibility.
    static let panelTint = Color.black.opacity(0.4)
    /// Reduce transparency: the glass becomes this solid dark surface.
    static let panelSolid = Color(hex: "1C1C1E")
    /// Increase contrast: 1 px edge on the panel only (never on cards).
    static let panelContrastEdge = Color.white.opacity(0.2)
    static let panelContrastEdgeWidth: CGFloat = 1

    /// Active-role glow: `linear-gradient(163.48deg, colour 4.22%, colour 0% 41.78%)`.
    static let glowAngleDegrees: Double = 163.48
    static let glowStart: CGFloat = 0.0422
    static let glowEnd: CGFloat = 0.4178
    static let tintAnimation: Double = 0.3

    // MARK: - Header

    static let headerHeight: CGFloat = 27
    static let headerButtonGap: CGFloat = 8
    static let headerButtonPaddingV: CGFloat = 5
    static let headerButtonPaddingH: CGFloat = 10
    static let headerButtonRadius: CGFloat = 6
    static let headerButtonFill = Color.black.opacity(0.10)
    static let menuButtonSize: CGFloat = 27
    static let menuIconSize: CGFloat = 13

    // MARK: - List

    static let listGap: CGFloat = 6
    static let listViewportIdle: CGFloat = 258
    static let listViewportActive: CGFloat = 192
    /// Fraction of the viewport that stays fully visible before the bottom fade.
    static let fadeStartIdle: CGFloat = 0.77
    static let fadeStartActive: CGFloat = 0.82
    /// Top fade: the top 12% of the viewport, once scrolled (PRD V10 Change 8).
    static let topFadeFraction: CGFloat = 0.12

    // MARK: - Footer

    static let footerGap: CGFloat = 10
    static let footerDotSize: CGFloat = 4
    static let footerOpacity: Double = 0.8
    static let footerHoverOpacity: Double = 1.0

    // MARK: - Card (Change 4, 5)

    static let cardHeight: CGFloat = 60
    static let cardExpandedHeight: CGFloat = 118
    static let cardPaddingV: CGFloat = 8
    static let cardPaddingH: CGFloat = 10
    static let cardRadius: CGFloat = 10
    static let cardColumnGap: CGFloat = 4
    static let cardRowGap: CGFloat = 10

    static let pillHeight: CGFloat = 23
    static let pillPadding: CGFloat = 5
    static let pillRadius: CGFloat = 20
    static let pillGap: CGFloat = 4
    static let pillInnerGap: CGFloat = 2
    static let pillIconSize: CGFloat = 10
    static let pillFill = Color.white.opacity(0.10)

    static let iconButtonSize: CGFloat = 28
    static let iconButtonIconSize: CGFloat = 12
    static let iconButtonFill = Color.black.opacity(0.20)

    static let hoverGradient = LinearGradient(
        colors: [Color.black.opacity(0), Color.black.opacity(0.20)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let hoverAnimation: Double = 0.15
    static let expandAnimation: Double = 0.2

    // MARK: - Start bar and timer chooser

    static let startBarHeight: CGFloat = 48
    static let startBarPadding: CGFloat = 10
    static let startBarFill = Color.black.opacity(0.60)
    static let startIconSize: CGFloat = 14
    static let startLabelGap: CGFloat = 4
    static let roundButtonSize: CGFloat = 28
    static let roundButtonFill = Color.white.opacity(0.20)
    static let roundButtonIconSize: CGFloat = 12

    static let chipGap: CGFloat = 3
    static let chipHeight: CGFloat = 26
    static let chipPaddingV: CGFloat = 5
    static let chipPaddingH: CGFloat = 10
    /// Only when five chips share the active section's capsule.
    static let chipPaddingHCompact: CGFloat = 6
    static let chipRadius: CGFloat = 24
    static let chipFill = Color.white.opacity(0.10)
    static let chipHoverFill = Color.white.opacity(0.20)
    static let customMinutesRange = 1 ... 600
    static let customFieldWidth: CGFloat = 52

    // MARK: - Active role section (Change 6)

    static let activePaddingV: CGFloat = 5
    static let activePaddingH: CGFloat = 10
    static let activeGap: CGFloat = 4
    static let activeTopRowHeight: CGFloat = 50
    static let endBarHeight: CGFloat = 37
    static let endBarFill = Color.black.opacity(0.40)

    // MARK: - Other surfaces (Section 11)

    static let rowRadius: CGFloat = 10
    static let rowPaddingV: CGFloat = 8
    static let rowPaddingH: CGFloat = 10
    static let rowFill = Color.white.opacity(0.06)
    static let fieldFill = Color.black.opacity(0.20)
    static let fieldRadius: CGFloat = 8
    static let bannerFill = Color.white.opacity(0.08)
    static let warningBannerFill = Color.orange.opacity(0.18)
    static let destructive = Color(red: 1.0, green: 0.42, blue: 0.42)
    /// Needs-attention text, e.g. "Choose a profile" on an unlinked Chrome row.
    static let attention = Color.orange
    static let selectionFill = Color.white.opacity(0.20)
    static let screenGap: CGFloat = 10
    static let sectionTitleGap: CGFloat = 6
    static let swatchHeight: CGFloat = 26
    static let swatchRadius: CGFloat = 6
    static let swatchGap: CGFloat = 6
    static let swatchSelectedEdge = Color.white.opacity(0.95)
    static let swatchSelectedEdgeWidth: CGFloat = 2
    static let appIconSize: CGFloat = 18
    static let listMaxHeight: CGFloat = 258
    static let smallButtonHeight: CGFloat = 28

    // MARK: - Text

    static let textPrimary = Color.white
    /// Opacities (Change 9 contrast minimums). Increase contrast lifts every
    /// secondary opacity to at least `contrastMinimum`.
    static let pillLabelOpacity: Double = 0.7
    static let valueOpacity: Double = 0.8
    static let timerLabelOpacity: Double = 0.6
    static let secondaryOpacity: Double = 0.7
    static let contrastMinimum: Double = 0.9

    static func opacity(_ base: Double, increasedContrast: Bool) -> Double {
        increasedContrast ? max(base, contrastMinimum) : base
    }

    // MARK: - Typography (system font only; export weight 510 = medium)

    enum FontStyle {
        case clock
        case headerTitle
        case title
        case button
        case footer
        case chip
        case timerLabel
        case pill
        case body
        case caption

        var font: Font {
            switch self {
            case .clock: return .system(size: 24, weight: .medium).monospacedDigit()
            case .headerTitle: return .system(size: 14, weight: .medium)
            case .title: return .system(size: 14, weight: .regular)
            case .button: return .system(size: 14, weight: .regular)
            case .footer: return .system(size: 13, weight: .regular)
            case .chip: return .system(size: 13, weight: .regular)
            case .timerLabel: return .system(size: 12, weight: .medium)
            case .pill: return .system(size: 11, weight: .regular).monospacedDigit()
            case .body: return .system(size: 13, weight: .regular)
            case .caption: return .system(size: 11, weight: .regular)
            }
        }
    }
}

extension View {
    func sessionCardFont(_ style: SessionCardStyles.FontStyle) -> some View {
        font(style.font)
    }
}

// MARK: - Palette

enum SessionCardSurfaceState {
    case `default`
    /// Hover, keyboard highlight and expanded share one look (Change 5).
    case elevated
}

enum SessionCardPalette {
    static func base(for color: ProfileColor) -> Color {
        color.color
    }

    @ViewBuilder
    static func cardBackground(color: ProfileColor, state: SessionCardSurfaceState) -> some View {
        ZStack {
            base(for: color)
            SessionCardStyles.hoverGradient
                .opacity(state == .elevated ? 1 : 0)
        }
    }

    /// The active role's glow from the top-left corner (Change 2). CSS
    /// angles run clockwise from "to top"; 163.48° points down and slightly
    /// right, so the gradient runs from near the top edge to the bottom.
    static func glow(for color: ProfileColor?) -> LinearGradient {
        let base = color?.color ?? .clear
        let radians = (SessionCardStyles.glowAngleDegrees - 90) * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(
            stops: [
                .init(color: base, location: SessionCardStyles.glowStart),
                .init(color: base.opacity(0), location: SessionCardStyles.glowEnd)
            ],
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }
}
