import AppKit
import SwiftUI

/// Owns the menu bar item and the panel hanging off it.
///
/// SwiftUI's `MenuBarExtra` closes itself whenever it loses focus and offers no
/// way to reopen it, which makes it unusable here: adding a folder means putting
/// a system picker on screen, and the panel has to survive that. An `NSPanel`
/// we control can stay open beside the picker, so the new row appears the
/// instant the user chooses.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var contentHeight: CGFloat?

    /// Set while a system picker is on screen. Outside clicks belong to the
    /// picker then, so the panel must ignore them instead of hiding itself.
    private var pickerDepth = 0

    var isPickerOpen: Bool { pickerDepth > 0 }

    init(model: AppModel) {
        self.model = model
        super.init()
        model.panel = self
    }

    // MARK: - Menu bar item

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarImage(accessibilityDescription: "Mevin")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshStatusIcon()
    }

    /// The icon carries the active profile's colour while a session runs, and is
    /// the only signal outside the panel that anything is running.
    ///
    /// Idle, the M is a template image the system paints to match the menu bar.
    /// Active, it is a copy filled with the role colour: the status bar ignores
    /// `contentTintColor` on template images (checked on macOS 27).
    func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }

        if model.notificationsDenied {
            button.image = menuBarImage(accessibilityDescription: "Mevin")
            button.contentTintColor = nil
            button.title = model.menuBarTimerLabel.map { "\($0) •" } ?? "•"
            return
        }

        guard let profile = model.activeProfile else {
            button.image = menuBarImage(accessibilityDescription: "Mevin")
            button.contentTintColor = nil
            button.title = ""
            return
        }

        button.image = menuBarImage(
            accessibilityDescription: "Mevin, running \(profile.name)",
            tint: profile.color.midTone
        )
        button.contentTintColor = nil
        button.title = model.menuBarTimerLabel ?? ""
    }

    /// The M from the asset catalog, 18 pt tall at its own aspect ratio. A copy,
    /// so the shared catalog image is never changed. With a tint, the M is drawn
    /// in that colour (still from the vector, so it stays sharp at any scale).
    private func menuBarImage(accessibilityDescription: String, tint: NSColor? = nil) -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon")?.copy() as? NSImage else { return nil }
        let height = SessionCardStyles.menuBarIconHeight
        image.size = NSSize(width: (height * image.size.width / image.size.height).rounded(), height: height)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        guard let tint else { return image }

        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceIn)
            return true
        }
        tinted.isTemplate = false
        tinted.accessibilityDescription = accessibilityDescription
        return tinted
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        toggle()
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Mevin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Panel lifecycle

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func bringPanelToFront() {
        guard let panel else { return }
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func show() {
        let panel = panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()
        // Text fields need key focus, which a non-activating panel will not take
        // on its own.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        startMonitors()
        model.panelDidOpen()
    }

    func hide() {
        stopMonitors()
        panel?.orderOut(nil)
        model.panelDidClose()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: SessionCardStyles.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // No forced appearance: the glass follows Light, Dark and Auto, and the
        // 40% black tint keeps the white text readable on either (PRD V8 Change 1).
        panel.delegate = self

        let root = MenuRootView()
            .environmentObject(model)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.contentMinSize = NSSize(width: SessionCardStyles.panelWidth, height: 80)

        self.panel = panel
        return panel
    }

    /// Hangs the panel under the menu bar item, nudged inward if that would put
    /// it off the edge of the screen.
    private func position(_ panel: NSPanel) {
        let measured = contentHeight ?? panel.contentView?.fittingSize.height ?? 240
        let height = min(max(measured, 80), maxPanelHeight)
        panel.setContentSize(NSSize(width: SessionCardStyles.panelWidth, height: height))

        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let gap: CGFloat = 6

        var x = buttonFrame.midX - SessionCardStyles.panelWidth / 2
        var y = buttonFrame.minY - height - gap

        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + gap), visible.maxX - SessionCardStyles.panelWidth - gap)
            if y < visible.minY + gap {
                y = visible.minY + gap
            }
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// SwiftUI reports its own height, which is more reliable than asking the
    /// hosting view mid-update, and keeps the panel hugging its content as
    /// screens swap and items are added.
    func updateContentHeight(_ height: CGFloat) {
        guard height > 0, abs((contentHeight ?? 0) - height) > 0.5 else { return }
        contentHeight = height
        guard let panel, panel.isVisible else { return }
        position(panel)
    }

    private var maxPanelHeight: CGFloat {
        guard let visible = (statusItem?.button?.window?.screen ?? NSScreen.main)?.visibleFrame else { return 700 }
        return visible.height - 24
    }

    // MARK: - Dismissal

    private func startMonitors() {
        stopMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.isPickerOpen else { return }
            Task { @MainActor in self.hide() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isPickerOpen { return event }
            if event.keyCode == 53 {
                if self.model.escapePressed() {
                    return nil
                }
                self.hide()
                return nil
            }
            if self.model.screen == .builder,
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v",
               self.model.pasteScreenshotIfPossible() {
                return nil
            }
            return event
        }
    }

    private func stopMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        outsideClickMonitor = nil
        keyMonitor = nil
    }

    // MARK: - System pickers

    /// Runs a system picker without letting the panel dismiss itself, and
    /// without blocking it, so the user sees the result land in the list.
    func runPicker(_ openPanel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
        pickerDepth += 1
        // The panel normally floats at menu level, which is above anything the
        // system puts up. Drop it while the picker is open so the picker is not
        // hidden behind the very panel it was opened from.
        panel?.level = .floating
        NSApp.activate(ignoringOtherApps: true)

        openPanel.begin { [weak self] response in
            let url = response == .OK ? openPanel.url : nil
            Task { @MainActor in
                guard let self else { return }
                self.pickerDepth = max(0, self.pickerDepth - 1)
                self.panel?.level = .popUpMenu
                completion(url)
                // The picker took focus; make sure the panel is still the thing
                // in front and still accepting keystrokes.
                self.show()
            }
        }
    }
}

/// A borderless window refuses key status by default, which would leave every
/// text field in the panel unable to accept a keystroke.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
