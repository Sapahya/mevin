import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Creating and editing are the same screen. A profile is a list the user
/// curated by hand, so this is where nearly all the product lives.
struct ProfileBuilderView: View {
    @EnvironmentObject private var model: AppModel

    private var draft: Profile? { model.draft }

    var body: some View {
        if let draft {
            content(draft)
        } else {
            Button("Back") { model.closeBuilder() }
        }
    }

    private func content(_ draft: Profile) -> some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            header(draft)

            Text("Add the apps, Chrome profile, links and folders this profile should open.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Permanent, whether the profile has zero items or twenty.
            HStack(alignment: .top, spacing: 8) {
                AddItemMenu()
                Button("Add what's open") {
                    model.addWhatsOpen()
                }
                .font(.caption)
                .fixedSize()
                .padding(.top, 5)
                .help("Add the apps (and Chrome tabs) that are running now")
            }

            ScreenshotDropZone()

            if let message = model.folderOpenerMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(SessionCardStyles.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch model.addMode {
            case .none:
                EmptyView()
            case .app:
                AppSearchList()
            case .chromeProfile:
                EmptyView()
            case .link:
                LinkFields()
            }

            if !draft.items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(draft.groupOrder, id: \.self) { group in
                            ItemGroupSection(group: group, draft: draft)
                        }
                    }
                }
                .frame(maxHeight: SessionCardStyles.listMaxHeight)
            }

            footer(draft)
        }
        // Section 11: every text button in the editor reads as a V8 chip unless
        // it sets its own style (Save, icon buttons).
        .buttonStyle(MevinChipButtonStyle())
        // Warmed here so the app search and the folder "Opens in" menu are ready
        // by the time either is opened.
        .onAppear { model.loadInstalledApps() }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            _ = model.handleScreenshotDrop(providers)
        }
        .overlay {
            if model.showingScreenshotConsent {
                ScreenshotConsentOverlay()
            }
        }
    }

    private func header(_ draft: Profile) -> some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.sectionTitleGap) {
            HStack(spacing: SessionCardStyles.headerButtonGap) {
                MevinIconButton(
                    symbol: "chevron.left",
                    label: "Close without saving",
                    fill: SessionCardStyles.roundButtonFill
                ) {
                    model.closeBuilder()
                }

                TextField(
                    "Profile name",
                    text: Binding(
                        get: { model.draft?.name ?? "" },
                        set: { model.renameDraft($0) }
                    )
                )
                .mevinField()
            }

            if let error = model.draftNameError {
                Text(error)
                    .sessionCardFont(.caption)
                    .foregroundStyle(SessionCardStyles.destructive)
            }

            // Editing the active role (PRD V8 Change 6).
            if !model.draftIsNew && model.isRunning(draft.id) {
                MevinSecondaryText("Changes apply next time you start this role.", style: .caption)
            }

            // The colour is chosen when the profile is created; this is where it
            // can be changed afterwards.
            ColorSwatchRow(
                selection: Binding(
                    get: { model.draft?.color ?? .fallback },
                    set: { model.setDraftColor($0) }
                )
            )

            DefaultTimerRow()
        }
    }

    /// Save only. Deleting lives in the panel menu (PRD V8 Change 7).
    private func footer(_ draft: Profile) -> some View {
        VStack(spacing: SessionCardStyles.sectionTitleGap) {
            Button("Save") {
                model.saveDraft()
            }
            .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!model.draftSaveIsValid)

            if model.draftNameIsValid && !model.draftHasItems {
                MevinSecondaryText("Add at least one app, link or folder. To delete this profile, use the menu.", style: .caption)
            } else if model.draftNameIsValid && !model.draftChromeIsValid {
                MevinSecondaryText("Link a Chrome profile to save this role.", style: .caption)
            }
        }
    }
}

// MARK: - Screenshot

private struct ScreenshotDropZone: View {
    @EnvironmentObject private var model: AppModel

    private var enabled: Bool { model.hasOpenAIKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop a screenshot of your apps")
                        .font(.caption)
                    if enabled {
                        Text("Or press Cmd+V to paste one.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add an OpenAI key in AI settings to read screenshots.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if enabled {
                    Button("Browse") {
                        model.browseForScreenshot()
                    }
                    .font(.caption)
                    .disabled(model.isReadingScreenshot)
                }
            }

            if model.isReadingScreenshot {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading screenshot…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = model.screenshotError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SessionCardStyles.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionCardStyles.rowFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))
        .opacity(enabled ? 1 : 0.7)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            model.handleScreenshotDrop(providers)
        }
    }
}

private struct ScreenshotConsentOverlay: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(alignment: .leading, spacing: 8) {
                Text("Send this image to OpenAI?")
                    .sessionCardFont(.headerTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mevin will send this one screenshot to OpenAI to read which apps are in it. Nothing else from your profiles is sent. This uses your own API key, so it's billed to your account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Don't ask again", isOn: $model.consentDontAskChecked)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel") {
                        model.cancelScreenshotConsent()
                    }
                    .font(.caption)
                    Spacer()
                    Button("Send") {
                        model.confirmScreenshotConsent()
                    }
                    .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
                    .font(.caption)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .background(SessionCardStyles.panelSolid, in: RoundedRectangle(cornerRadius: SessionCardStyles.panelRadius))
            .padding(16)
        }
    }
}

// MARK: - Add control

private struct AddItemMenu: View {
    @EnvironmentObject private var model: AppModel

    /// A count tells the user what is already in the profile without making them
    /// close the menu to look.
    private func title(_ base: String, _ count: Int) -> String {
        count > 0 ? "\(base) (\(count))" : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Menu {
                Button {
                    model.addMode = .app
                    model.loadInstalledApps()
                } label: {
                    Label(
                        title("App", model.draft?.items(in: .apps).count ?? 0),
                        systemImage: "app.badge"
                    )
                }

                Button {
                    model.addMode = .link
                } label: {
                    Label(
                        title("Link", model.draft?.links.count ?? 0),
                        systemImage: "link"
                    )
                }

                Button {
                    model.browseForFolder()
                } label: {
                    Label(
                        title("Folder", model.draft?.items(in: .folders).count ?? 0),
                        systemImage: "folder"
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption)
                    Text("Add apps, links, folders…")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(SessionCardStyles.rowFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))

        }
    }
}

// MARK: - Item groups

private struct ItemGroupSection: View {
    @EnvironmentObject private var model: AppModel
    let group: ItemGroup
    let draft: Profile

    private var rows: [ProfileItem] {
        draft.items(in: group)
    }

    private var links: [ProfileItem] {
        group == .chromeWithLinks ? draft.links : []
    }

    private var isEmpty: Bool {
        rows.isEmpty && links.isEmpty
    }

    /// A links-only profile should not be headed "Chrome profile", so the group
    /// takes its name from what it actually contains.
    private var title: String {
        group == .chromeWithLinks && rows.isEmpty ? "Links" : group.heading
    }

    var body: some View {
        if !isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                heading

                ForEach(rows) { item in
                    ItemRow(item: item)
                }

                if group == .chromeWithLinks {
                    if !links.isEmpty {
                        // Links render immediately after the Chrome profile and
                        // cannot be separated from it: they are arguments to the
                        // same launch command.
                        if !rows.isEmpty {
                            Text("Links")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }

                        ForEach(links) { item in
                            ItemRow(item: item)
                        }
                        addAnother("Add another link") { model.addMode = .link }
                    }
                } else {
                    addAnother(group == .apps ? "Add another app" : "Add another folder") {
                        if group == .apps {
                            model.addMode = .app
                            model.loadInstalledApps()
                        } else {
                            model.browseForFolder()
                        }
                    }
                }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // Three groups at most, so up and down beat a nested drag target in
            // a 340pt panel.
            MevinIconButton(symbol: "chevron.up", label: "Open this group earlier") {
                model.moveGroup(group, by: -1)
            }
            .disabled(draft.groupOrder.first == group)

            MevinIconButton(symbol: "chevron.down", label: "Open this group later") {
                model.moveGroup(group, by: 1)
            }
            .disabled(draft.groupOrder.last == group)
        }
    }

    private func addAnother(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: ProfileItem

    private var isFlashed: Bool {
        model.flashedItemID == item.id
    }

    /// On Keep open. The profile still opens it; nothing will ever close it.
    private var isAlwaysOpen: Bool {
        item.type == .app && model.isKeptOpen(item.bundleId)
    }

    private var supportsDestination: Bool {
        item.type == .app && (
            item.bundleId == Constants.claudeBundleID
                || item.bundleId == Constants.figmaBundleID
                || item.bundleId == Constants.slackBundleID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if supportsDestination, item.destination != nil || model.destinationEditingItemID == item.id {
                DestinationControl(item: item)
            }
            if item.type == .chromeProfile {
                ChromeProfileControl(item: item)
            }
            if item.type == .app, item.bundleId == Constants.terminalBundleID {
                TerminalTabsControl(item: item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            isFlashed ? SessionCardStyles.selectionFill : SessionCardStyles.rowFill,
            in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius)
        )
        .animation(.easeOut(duration: 0.25), value: isFlashed)
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first, let draggedID = UUID(uuidString: raw) else { return false }
            model.moveItem(draggedID: draggedID, onto: item.id)
            return true
        }
    }

    private var mainRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")

            ItemIcon(item: item)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let summary = item.terminalRowSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let note = model.lastTimeNote(for: item.bundleId) {
                    Text("Last time: \(note)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if isAlwaysOpen {
                Text("Always open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SessionCardStyles.pillFill, in: Capsule())
                    .help("On Always open, so Mevin will never close it")
            }

            if item.type == .folder {
                FolderOpenerMenu(item: item)
            }

            if supportsDestination,
               item.destination == nil,
               model.destinationEditingItemID != item.id {
                Button("Open a specific page") {
                    model.beginDestinationEdit(itemID: item.id)
                }
                .font(.caption)
            }

            MevinIconButton(symbol: "trash", label: "Remove \(item.label)") {
                model.removeItem(id: item.id)
            }
        }
        // Dimmed because the close half of the promise does not apply to it.
        .opacity(isAlwaysOpen ? 0.65 : 1)
    }
}

/// Terminal app row: folder + command per tab (PRD V5).
private struct TerminalTabsControl: View {
    @EnvironmentObject private var model: AppModel
    let item: ProfileItem

    private var tabs: [TerminalTab] {
        item.terminalTabs ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tabs) { tab in
                TerminalTabRow(itemID: item.id, tab: tab)
            }
            Button("+ Add tab") {
                model.addTerminalTab(itemID: item.id)
            }
            .font(.caption)
            if !tabs.isEmpty {
                Text("Commands are saved as plain text on this Mac. Don't include passwords or API keys.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 22)
    }
}

private struct TerminalTabRow: View {
    @EnvironmentObject private var model: AppModel
    let itemID: UUID
    let tab: TerminalTab

    private var commandBinding: Binding<String> {
        Binding(
            get: { model.terminalTabCommand(itemID: itemID, tabID: tab.id) },
            set: { model.setTerminalTabCommand(itemID: itemID, tabID: tab.id, command: $0) }
        )
    }

    private var folderLabel: String {
        guard let path = tab.path, !path.isEmpty else {
            return "Home folder (default)"
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Choose folder…") {
                    model.browseForTerminalTabFolder(itemID: itemID, tabID: tab.id)
                }
                .font(.caption)
                Text(folderLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                MevinIconButton(symbol: "xmark", label: "Remove tab") {
                    model.removeTerminalTab(itemID: itemID, tabID: tab.id)
                }
            }
            TextField("Command", text: commandBinding, prompt: Text("e.g. npm run dev"))
                .mevinField()
                .font(.caption)
        }
        .padding(6)
        .background(SessionCardStyles.rowFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))
    }
}

/// Chrome profile linking on the Chrome row (PRD V2).
private struct ChromeProfileControl: View {
    @EnvironmentObject private var model: AppModel
    let item: ProfileItem

    private var isEditing: Bool {
        model.chromeEditingItemID == item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                ChromeProfilePanel(itemID: item.id)
            } else if item.isChromeLinked {
                HStack(spacing: 10) {
                    Text("Opens profile: \(item.displayName ?? item.directory ?? "Chrome")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change") {
                        model.beginChromeEdit(itemID: item.id)
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Choose a profile")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SessionCardStyles.attention)
                    Button("Choose") {
                        model.beginChromeEdit(itemID: item.id)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.leading, 22)
    }
}

private struct ChromeProfilePanel: View {
    @EnvironmentObject private var model: AppModel
    let itemID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch Chrome to the profile you want, then click Detect.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.detectChromeProfile()
            } label: {
                Label("Detect profile", systemImage: "viewfinder")
                    .font(.caption.weight(.semibold))
            }
            .disabled(model.chromeDetecting)

            if model.chromeDetecting {
                Text("Detecting… copy Profile Path in Chrome if this takes a while.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let status = model.chromeDetectStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let reused = model.chromeProfilesUsedElsewhere()
            if !reused.isEmpty {
                Text("Profiles from your other roles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Profiles already used in another role share tabs between those roles.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(reused) { account in
                    Button {
                        model.addChromeProfile(account)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                            Text(account.displayName)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                _ = ChromeService.openManageProfiles()
            } label: {
                Label("Create new profile in Chrome", systemImage: "person.crop.circle.badge.plus")
                    .font(.caption)
            }

            if case .ok(let accounts) = model.chromeLookup, !accounts.isEmpty {
                Text("Or pick from Chrome")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(accounts) { account in
                    Button {
                        model.addChromeProfile(account)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text(account.displayName)
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                chromeLookupMessage
            }

            DisclosureGroup("Enter manually") {
                ManualChromeEntry(saveTitle: "Save", onCancel: { model.cancelChromeEdit() })
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var chromeLookupMessage: some View {
        switch model.chromeLookup {
        case .blockedBySystem:
            Text(ChromeService.systemBlockExplanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .notInstalled:
            Text("Google Chrome isn’t installed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .neverLaunched:
            Text("Open Chrome once, then link a profile with chrome://version.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .unreadable(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .ok:
            EmptyView()
        }
    }
}

/// Only offered on Claude, Figma and Slack app rows. One field, one paste.
/// The id is never shown.
private struct DestinationControl: View {
    @EnvironmentObject private var model: AppModel
    let item: ProfileItem

    private var isEditing: Bool {
        model.destinationEditingItemID == item.id
    }

    private var isFigma: Bool {
        item.bundleId == Constants.figmaBundleID
    }

    private var isSlack: Bool {
        item.bundleId == Constants.slackBundleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                editor
            } else if item.destination != nil {
                setState
            }
        }
        .padding(.leading, 22)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                isFigma
                    ? "Paste a Figma link"
                    : isSlack
                        ? "Paste a Slack workspace or channel link"
                        : "Paste a Claude link or a session id",
                text: $model.destinationPasteText
            )
            .mevinField()
            .font(.caption)
            .onSubmit { model.addDestination(itemID: item.id) }
            .onChange(of: model.destinationPasteText) { _, _ in
                model.updateDestinationPaste()
            }

            Text(
                isFigma
                    ? "Right-click a page or section in Figma, copy its link, and paste it here."
                    : isSlack
                        ? "Copy a Slack link to a workspace or channel, then paste it here."
                        : "Copy the address from Claude, or paste just an id. We'll work out the rest."
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.destinationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(SessionCardStyles.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Add") {
                model.addDestination(itemID: item.id)
            }
            .font(.caption)
            .disabled(!model.destinationPasteIsValid)
        }
    }

    private var setState: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let destination = item.destination, !destination.isDesktopInstalled {
                Text("Opens in your browser, \(isFigma ? "Figma" : isSlack ? "Slack" : "Claude") isn't installed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Change") {
                    model.beginDestinationEdit(itemID: item.id)
                }
                .font(.caption)
                Button("Remove destination") {
                    model.clearDestination(itemID: item.id)
                }
                .font(.caption)
            }
        }
    }
}

private struct ItemIcon: View {
    let item: ProfileItem

    var body: some View {
        switch item.type {
        case .app:
            if let bundleId = item.bundleId, let icon = NSWorkspace.shared.icon(forBundleID: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(.secondary)
            }
        case .chromeProfile:
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        case .link:
            // A favicon would mean a network call, and this app makes none.
            Image(systemName: "link")
                .foregroundStyle(.secondary)
        case .folder:
            if let path = item.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FolderOpenerMenu: View {
    @EnvironmentObject private var model: AppModel
    let item: ProfileItem

    var body: some View {
        Menu {
            Button("Finder") {
                model.setFolderOpener(itemID: item.id, app: nil)
            }
            ForEach(model.folderOpenerChoices) { app in
                Button(app.name) {
                    model.setFolderOpener(itemID: item.id, app: app)
                }
            }
            Divider()
            Button("Other app…") {
                model.browseForFolderOpener(itemID: item.id)
            }
        } label: {
            Text("\(item.opensInLabel) ▾")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change which app opens this folder")
    }
}

// MARK: - Add flows

/// Typing beats browsing a folder of icons, and nothing external opens, so the
/// panel never has to be restored.
private struct AppSearchList: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search apps", text: $model.appQuery)
                .mevinField()
                .focused($searchFocused)
                .onSubmit(addHighlighted)
                .onKeyPress(.upArrow) {
                    model.appHighlightIndex = max(0, model.appHighlightIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.appHighlightIndex = min(
                        max(0, model.filteredApps.count - 1),
                        model.appHighlightIndex + 1
                    )
                    return .handled
                }
                .onChange(of: model.appQuery) { _, _ in
                    model.appHighlightIndex = 0
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.filteredApps.prefix(50).enumerated()), id: \.element.id) { index, app in
                        Button {
                            model.addApp(bundleId: app.bundleId, name: app.name)
                        } label: {
                            HStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                index == model.appHighlightIndex
                                    ? SessionCardStyles.selectionFill
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: SessionCardStyles.fieldRadius)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Button("Browse…") {
                    model.browseForApp()
                }
                .font(.caption)
                Spacer()
                Button("Done") {
                    model.addMode = .none
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(SessionCardStyles.rowFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))
        .onAppear { searchFocused = true }
    }

    private func addHighlighted() {
        let apps = model.filteredApps
        guard model.appHighlightIndex < apps.count else { return }
        let app = apps[model.appHighlightIndex]
        model.addApp(bundleId: app.bundleId, name: app.name)
    }
}

/// The user supplies the profile folder name and what to call it. Since Mevin
/// cannot check the name against Chrome's own list, Test it launches the profile
/// so the user can verify it themselves before committing. Step copy from
/// PRD V10 Change 6.
private struct ManualChromeEntry: View {
    @EnvironmentObject private var model: AppModel
    var saveTitle: String = "Add"
    var onCancel: (() -> Void)?
    @FocusState private var pathFocused: Bool

    /// The folder name, only when it looks like one of Chrome's own.
    private var resolved: String? {
        guard let folder = model.chromeDirectoryFromEntry,
              ChromeService.isLikelyProfileDirectory(folder) else { return nil }
        return folder
    }

    private var showsInvalid: Bool {
        resolved == nil && !model.chromeDirectoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Link a Chrome profile")
                .font(.caption.weight(.semibold))

            step("1. Go to the right profile.")
            hint("In Chrome, click the profile picture at the top right and switch to the profile this role should use.")

            step("2. Copy its Profile Path.")
            hint("In that same window, open a new tab, paste chrome://version and press Return. Copy the text next to Profile Path.")
            Button {
                model.copyChromeVersionAddress()
            } label: {
                Label("Copy chrome://version", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            hint("Check the profile picture first. This page shows the path of the window it's opened in.")

            step("3. Paste it here.")
            TextField("Paste the Profile Path", text: $model.chromeDirectoryText)
                .mevinField()
                .focused($pathFocused)
                .onChange(of: model.chromeDirectoryText) { _, _ in
                    model.chromeManualEntryDidEditPath()
                }
            if let resolved {
                Text("Chrome profile folder: \(resolved)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if showsInvalid {
                Text("That isn't a Chrome profile path. It should end in \"Default\" or \"Profile\" and a number.")
                    .font(.caption2)
                    .foregroundStyle(SessionCardStyles.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step("4. Name it.")
            Text("Name in Mevin")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("e.g. Work", text: $model.chromeLabelText)
                .mevinField()
            hint("Only shown in Mevin. It doesn't need to match the name in Chrome.")

            if let error = model.chromeEntryError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SessionCardStyles.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step("5. Test it.")
            HStack {
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .font(.caption)
                }
                Button("Test it") {
                    model.testChromeProfileEntry()
                }
                .disabled(resolved == nil)
                .help("Opens Chrome on this profile so you can check it's the right one")

                Spacer()

                Button(saveTitle) {
                    model.addChromeProfileFromEntry()
                }
                .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
                .disabled(resolved == nil)
            }

            if model.chromeDidTest {
                hint("Chrome should now show this profile's picture at the top right. Wrong one? Go back to step 1, switch profiles, and copy the path again.")
            }
        }
        .onAppear { pathFocused = true }
    }

    private func step(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.top, 2)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LinkFields: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var urlFocused: Bool

    private var canAdd: Bool {
        ProfileItem.normalizedURL(model.linkURLText) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name this link", text: $model.linkTitleText)
                .mevinField()
            Text("Leave this blank and we’ll use the site name.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("https://", text: $model.linkURLText)
                .mevinField()
                .focused($urlFocused)
                .onSubmit { if canAdd { model.addLinkFromDraftFields() } }
                .onChange(of: model.linkURLText) { _, _ in
                    model.linkError = nil
                }

            if let error = model.linkError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SessionCardStyles.destructive)
            }

            HStack {
                Button("Add link") {
                    model.addLinkFromDraftFields()
                }
                .disabled(!canAdd)
                Spacer()
                Button("Done") {
                    model.addMode = .none
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(SessionCardStyles.rowFill, in: RoundedRectangle(cornerRadius: SessionCardStyles.rowRadius))
        .onAppear { urlFocused = true }
    }
}

private struct DefaultTimerRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Default session timer")
                .sessionCardFont(.timerLabel)
                .foregroundStyle(SessionCardStyles.textPrimary)
            Picker("Default timer", selection: binding) {
                Text("None").tag(Optional<Int>.none)
                Text("25m").tag(Optional(25))
                Text("50m").tag(Optional(50))
                Text("90m").tag(Optional(90))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var binding: Binding<Int?> {
        Binding(
            get: { model.draft?.defaultTimerMinutes },
            set: { model.setDraftDefaultTimer(minutes: $0) }
        )
    }
}
