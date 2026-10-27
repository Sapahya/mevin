import AppKit
import SwiftUI

/// The panel's home screen (PRD V8 Changes 3 and 6): header, the active role
/// section, banners, the profile list in a fading viewport, and the footer.
struct ProfileListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let active = model.activeProfile
        VStack(alignment: .leading, spacing: active == nil ? SessionCardStyles.sectionGapIdle : SessionCardStyles.sectionGapActive) {
            PanelHeader()

            // V11 Change 1: at the top of the panel, above the active role.
            if model.accessibilityOff {
                AccessibilityOffBanner()
            }

            if let active {
                ActiveRoleSection(profile: active)
            }

            banners

            if model.profiles.isEmpty {
                emptyState
            } else if !model.listProfiles.isEmpty {
                ProfileListViewport(activeRole: active != nil)
            }

            PanelFooter()
        }
    }

    /// V7 banners sit between the active section and the list (Change 6).
    @ViewBuilder
    private var banners: some View {
        if let id = model.deletingProfileID, let profile = model.profile(id: id) {
            DeleteConfirmBanner(profile: profile)
        }
        if let report = model.startReport {
            FailureReport(report: report)
        }
        if let banner = model.autoEndBanner {
            AutoEndBannerView(banner: banner)
        }
        if model.inAppTimerPrompt {
            InAppTimerPromptView()
        }
        if model.inAppCheckInPrompt {
            InAppCheckInPromptView()
        }
        if let blockID = model.terminalBlockProfileID {
            TerminalFingerprintBanner(profileID: blockID)
        }
    }

    private var emptyState: some View {
        MevinSecondaryText("Create a profile for each kind of work you do. A profile opens the apps, the Chrome profile, the links and the folders that belong to it, in one click.")
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SessionCardStyles.screenGap)
    }
}

// MARK: - Header and menu

private struct PanelHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Text("Profiles")
                .sessionCardFont(.headerTitle)
                .foregroundStyle(SessionCardStyles.textPrimary)
            Spacer()
            HStack(spacing: SessionCardStyles.headerButtonGap) {
                Button {
                    model.startNewProfile()
                } label: {
                    Text("Add Profile")
                        .sessionCardFont(.button)
                        .foregroundStyle(SessionCardStyles.textPrimary)
                        .padding(.vertical, SessionCardStyles.headerButtonPaddingV)
                        .padding(.horizontal, SessionCardStyles.headerButtonPaddingH)
                        .frame(height: SessionCardStyles.headerHeight)
                        .background(SessionCardStyles.headerButtonFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.headerButtonRadius))
                        .contentShape(RoundedRectangle(cornerRadius: SessionCardStyles.headerButtonRadius))
                }
                .buttonStyle(.plain)

                PanelMenu()
            }
        }
        .frame(height: SessionCardStyles.headerHeight)
    }
}

/// Native menu, so it follows the system look (Change 3).
private struct PanelMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Menu("Delete a profile…") {
                ForEach(model.profiles) { profile in
                    let active = model.isRunning(profile.id)
                    Button {
                        model.requestDelete(profileID: profile.id)
                    } label: {
                        Label {
                            Text(active ? "\(profile.name) (active)" : profile.name)
                        } icon: {
                            Image(nsImage: ColorDot.image(for: profile.color))
                        }
                    }
                    .disabled(active)
                }
            }
            .disabled(model.profiles.isEmpty)

            Button("AI settings") { model.showAISettings() }
            Button("Settings") { model.showSettings() }
            Divider()
            Button("Quit Mevin") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: SessionCardStyles.menuIconSize))
                .foregroundStyle(SessionCardStyles.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: SessionCardStyles.menuButtonSize, height: SessionCardStyles.menuButtonSize)
        .background(SessionCardStyles.headerButtonFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.headerButtonRadius))
        .contentShape(RoundedRectangle(cornerRadius: SessionCardStyles.headerButtonRadius))
        .help("Menu")
        .accessibilityLabel("Menu")
    }
}

/// Colour dot for menu items, drawn once per colour (menus need an NSImage).
@MainActor
private enum ColorDot {
    private static var cache: [ProfileColor: NSImage] = [:]

    static func image(for color: ProfileColor) -> NSImage {
        if let cached = cache[color] { return cached }
        let fill = color.midTone
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        cache[color] = image
        return image
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: SessionCardStyles.footerGap) {
            FooterLink(title: "Quit all") { model.beginQuitAllTabs() }
            Circle()
                .fill(SessionCardStyles.textPrimary)
                .frame(width: SessionCardStyles.footerDotSize, height: SessionCardStyles.footerDotSize)
                .opacity(SessionCardStyles.footerOpacity)
                .accessibilityHidden(true)
            FooterLink(title: "Always open") { model.showKeepOpen() }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FooterLink: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text(title)
                .sessionCardFont(.footer)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .opacity(hovering
                    ? SessionCardStyles.footerHoverOpacity
                    : SessionCardStyles.opacity(SessionCardStyles.footerOpacity, increasedContrast: contrast == .increased))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - List viewport

/// Fixed-height scrolling viewport (258 idle, 192 with an active role) that
/// shrinks to fit shorter content (V8 Change 3). The bottom fade weakens as the
/// end of the list comes into view and the top fade grows once scrolled, both
/// following the scroll position directly (V10 Change 8). The fades are an
/// alpha mask, so faded cards still click.
private struct ProfileListViewport: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activeRole: Bool

    @FocusState private var listFocused: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    /// Once the scroll view reports directly, the preference fallback is ignored.
    @State private var scrollReaderActive = false
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// The highlight only shows once arrow keys are used, so a lone card is
    /// never permanently highlighted (Change 8).
    @State private var keyboardActive = false

    private var maxHeight: CGFloat {
        activeRole ? SessionCardStyles.listViewportActive : SessionCardStyles.listViewportIdle
    }

    private var fadeStart: CGFloat {
        activeRole ? SessionCardStyles.fadeStartActive : SessionCardStyles.fadeStartIdle
    }

    private var viewportHeight: CGFloat {
        contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight
    }

    private var scrolls: Bool {
        contentHeight > maxHeight + 0.5
    }

    /// 1 while at least one fade height is still below, 0 once the last
    /// profile is fully in view.
    private var bottomFadeStrength: CGFloat {
        guard scrolls else { return 0 }
        let below = contentHeight - (scrollOffset + viewportHeight)
        let fadeHeight = viewportHeight * (1 - fadeStart)
        return min(max(below / fadeHeight, 0), 1)
    }

    /// 0 at the top of the list, 1 once one top-fade height has scrolled past.
    private var topFadeStrength: CGFloat {
        guard scrolls else { return 0 }
        let fadeHeight = viewportHeight * SessionCardStyles.topFadeFraction
        return min(max(scrollOffset / fadeHeight, 0), 1)
    }

    var body: some View {
        let profiles = model.listProfiles
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SessionCardStyles.listGap) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileCard(
                            profile: profile,
                            isHighlighted: keyboardActive && listFocused && index == model.listHighlight,
                            onHover: { hovering in if hovering { keyboardActive = false } }
                        )
                        .id(profile.id)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CardFramesKey.self,
                                    value: [profile.id: geo.frame(in: .named(Self.space))]
                                )
                            }
                        )
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: geo.size.height)
                            .preference(key: ScrollOffsetKey.self, value: -geo.frame(in: .named(Self.space)).minY)
                    }
                )
                .background(
                    ScrollPositionReader { offset in
                        scrollReaderActive = true
                        scrollOffset = offset
                    }
                )
            }
            .coordinateSpace(name: Self.space)
            .frame(height: viewportHeight)
            .mask(fadeMask)
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                if !scrollReaderActive { scrollOffset = offset }
            }
            .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onAppear {
                model.listHighlight = 0
                DispatchQueue.main.async { listFocused = true }
            }
            .onKeyPress(.upArrow) {
                keyboardActive = true
                model.listHighlight = max(0, model.listHighlight - 1)
                reveal(profiles, index: model.listHighlight, proxy: proxy)
                return .handled
            }
            .onKeyPress(.downArrow) {
                keyboardActive = true
                model.listHighlight = min(profiles.count - 1, model.listHighlight + 1)
                reveal(profiles, index: model.listHighlight, proxy: proxy)
                return .handled
            }
            // Return starts the highlighted card directly (Change 5).
            .onKeyPress(.return) {
                guard profiles.indices.contains(model.listHighlight) else { return .ignored }
                model.startOrEndSession(profileID: profiles[model.listHighlight].id)
                return .handled
            }
            .onChange(of: model.expandedProfileID) { _, expanded in
                guard let expanded else { return }
                // Wait for the expand animation, then make sure the whole
                // 118 card (and its Start bar) is clear of the fade.
                DispatchQueue.main.asyncAfter(deadline: .now() + SessionCardStyles.expandAnimation + 0.05) {
                    revealIfNeeded(expanded, proxy: proxy)
                }
            }
        }
    }

    private var fadeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(1 - topFadeStrength), location: 0),
                .init(color: .black, location: SessionCardStyles.topFadeFraction),
                .init(color: .black, location: fadeStart),
                .init(color: .black.opacity(1 - bottomFadeStrength), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func reveal(_ profiles: [Profile], index: Int, proxy: ScrollViewProxy) {
        guard profiles.indices.contains(index) else { return }
        revealIfNeeded(profiles[index].id, proxy: proxy)
    }

    /// Scrolls only when the card is cut off at the top or reaches into the
    /// fade (or past the bottom edge).
    private func revealIfNeeded(_ id: UUID, proxy: ScrollViewProxy) {
        guard let frame = cardFrames[id] else { return }
        // The last card scrolls to the very bottom, where the fade is gone.
        let isLast = model.listProfiles.last?.id == id
        let clearBottom = viewportHeight * (isLast || bottomFadeStrength == 0 ? 1 : fadeStart)
        let cutTop = frame.minY < 0
        let cutBottom = frame.maxY > clearBottom + 0.5
        guard cutTop || cutBottom else { return }
        let anchor: UnitPoint = cutTop ? .top : (isLast ? .bottom : .top)
        if reduceMotion {
            proxy.scrollTo(id, anchor: anchor)
        } else {
            withAnimation(.easeInOut(duration: SessionCardStyles.expandAnimation)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    private static let space = "profileList"
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Reports how far the enclosing scroll view is scrolled, on every scroll.
/// A SwiftUI preference read through GeometryReader often stops updating
/// while scrolling on macOS 14, which left the bottom fade stuck on (V10
/// Change 8); the clip view's bounds notification doesn't.
private struct ScrollPositionReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard window != nil, let clip = enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            report()
        }

        private func report() {
            guard let scrollView = enclosingScrollView, let document = scrollView.documentView else { return }
            let clip = scrollView.contentView.bounds
            let offset = document.isFlipped ? clip.minY : document.frame.height - clip.maxY
            onChange?(offset)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private struct CardFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Banners

private struct DeleteConfirmBanner: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            Text("Delete \(profile.name)? Its apps, links, Terminal tabs and history will be removed. This can't be undone.")
                .sessionCardFont(.body)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SessionCardStyles.headerButtonGap) {
                Button("Cancel") { model.cancelDelete() }
                    .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
                Button("Delete") { model.confirmDelete() }
                    .buttonStyle(MevinCapsuleButtonStyle(prominent: true, destructive: true))
            }
        }
        .mevinRow(fill: SessionCardStyles.bannerFill)
    }
}

/// Failures are actionable here, because the moment something fails to open is
/// exactly when the user knows whether they want it gone.
private struct FailureReport: View {
    @EnvironmentObject private var model: AppModel
    let report: StartReport

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.activeGap) {
            ForEach(Array(report.failures.enumerated()), id: \.offset) { index, failure in
                HStack(alignment: .center, spacing: SessionCardStyles.activeGap) {
                    MevinSecondaryText(failure.label, style: .caption)
                    Spacer(minLength: 6)
                    if failure.removable {
                        Button("Remove") {
                            model.removeFailedItem(profileID: report.profileId, itemID: failure.id)
                        }
                        .buttonStyle(MevinChipButtonStyle())
                    }
                    if index == 0 {
                        MevinIconButton(symbol: "xmark", label: "Dismiss", fill: .clear) {
                            model.dismissStartReport()
                        }
                    }
                }
            }
        }
        .mevinRow(fill: SessionCardStyles.bannerFill)
    }
}

private struct AutoEndBannerView: View {
    @EnvironmentObject private var model: AppModel
    let banner: AutoEndBanner

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: banner.lastActivityAt)
    }

    var body: some View {
        BannerWithActions(
            message: "\(banner.profileName) ended while you were away (last activity \(timeText)). Start it again?",
            actions: [("Start", { model.startFromAutoEndBanner() }), ("Dismiss", { model.dismissAutoEndBanner() })]
        )
    }
}

private struct InAppTimerPromptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BannerWithActions(
            message: "\(model.activeProfile?.name ?? "Role"): time's up. Do you want to continue?",
            actions: [
                ("New timer", { model.openPanelForNewTimerAfterExpiry() }),
                ("Continue without timer", { model.continueAfterTimerWithoutExtension() })
            ]
        )
    }
}

private struct InAppCheckInPromptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BannerWithActions(
            message: "Still using \"\(model.activeProfile?.name ?? "Role")\"?",
            actions: [
                ("Yes, continue", { model.respondToCheckInContinue() }),
                ("End session", { model.respondToCheckInEnd() })
            ]
        )
    }
}

private struct AccessibilityOffBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BannerWithActions(
            message: "Mevin can't see your windows. Turn on Accessibility so it can switch Chrome profiles and close the right windows.",
            actions: [("Open Settings", { model.openAccessibilitySettings() })],
            fill: SessionCardStyles.warningBannerFill
        )
    }
}

private struct TerminalFingerprintBanner: View {
    @EnvironmentObject private var model: AppModel
    let profileID: UUID

    var body: some View {
        BannerWithActions(
            message: "This role's Terminal commands were changed outside Mevin. Review them before they run.",
            actions: [
                ("Review", { model.reviewTerminalCommands(for: profileID) }),
                ("Run", { model.runTerminalAnyway(for: profileID) })
            ],
            fill: SessionCardStyles.warningBannerFill
        )
    }
}

private struct BannerWithActions: View {
    let message: String
    let actions: [(String, () -> Void)]
    var fill: Color = SessionCardStyles.bannerFill

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.headerButtonGap) {
            Text(message)
                .sessionCardFont(.body)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SessionCardStyles.headerButtonGap) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.0, action: action.1)
                        .buttonStyle(MevinChipButtonStyle())
                }
            }
        }
        .mevinRow(fill: fill)
    }
}
