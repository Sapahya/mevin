import AppKit
import SwiftUI

/// The panel is the whole interface, so each step swaps in here rather than
/// opening a window of its own.
struct MenuRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.screen {
            case .list:
                ProfileListView()
            case .newProfile:
                NewProfileView()
            case .builder:
                ProfileBuilderView()
            case .keepOpen:
                KeepOpenView()
            case .aiSettings:
                AISettingsView()
            case .settings:
                SettingsView()
            case .proposal:
                ProposalSheet()
            case .keepOpenConfirm:
                KeepOpenConfirmView()
            case .quitConfirm:
                QuitAllTabsConfirmView()
            }
        }
        .frame(width: SessionCardStyles.contentWidth)
        .padding(SessionCardStyles.panelPadding)
        .fixedSize(horizontal: false, vertical: true)
        // The panel is sized from what SwiftUI actually laid out, so it keeps
        // hugging the content as screens swap and items are added.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { height in
            model.panel?.updateContentHeight(height)
        }
        // Text and controls are white on the 40% black tint in both Light and
        // Dark, so the content resolves as dark; the glass beneath follows the
        // system appearance (PRD V8 Change 1).
        .environment(\.colorScheme, .dark)
        .background(PanelSurface(activeColor: model.activeProfile?.color))
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Glass, then black 40%, then the active role's glow (PRD V8 Changes 1, 2).
/// Reduce transparency swaps the glass for a solid dark surface; Increase
/// contrast adds a 1 px edge. Both update live.
private struct PanelSurface: View {
    let activeColor: ProfileColor?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SessionCardStyles.panelRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                SessionCardStyles.panelSolid
            } else {
                PanelGlass()
            }
            SessionCardStyles.panelTint
            SessionCardPalette.glow(for: activeColor)
                .opacity(activeColor == nil ? 0 : 1)
        }
        .clipShape(shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(SessionCardStyles.panelContrastEdge, lineWidth: SessionCardStyles.panelContrastEdgeWidth)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: SessionCardStyles.tintAnimation), value: activeColor)
    }
}

/// Liquid Glass on macOS 26 and later; the menu material blur on 14 and 15.
/// No appearance is forced, so the glass follows Light, Dark and Auto.
private struct PanelGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = SessionCardStyles.panelRadius
            return glass
        }
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
