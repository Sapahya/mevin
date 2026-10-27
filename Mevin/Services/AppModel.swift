import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeSession: ActiveSession?
    @Published var screen: Screen = .list
    /// Apps that are never closed, whichever profile is running. Global, not
    /// per-profile, and it grants immunity from closing only: being on this list
    /// never causes an app to open.
    @Published var keepOpenBundleIds: [String] = []
    @Published var snapshots: [SessionSnapshot] = []
    @Published var chromeWindowBindings: [String: Int] = [:]
    @Published var roleUses: [RoleUseRecord] = []
    @Published var checkInIntervalHours: Int = 3
    @Published var autoEndBanner: AutoEndBanner?
    @Published var activeTimerMinutes: Int?
    @Published var timerRepeatPrefillMinutes: Int?
    @Published var notificationsDenied = false
    /// V11 Change 1: Accessibility is off, so Mevin can't read or move windows.
    @Published var accessibilityOff = !AccessibilityWindowControl.isTrusted()
    @Published var inAppTimerPrompt = false
    @Published var inAppCheckInPrompt = false

    @Published var keepOpenMode: KeepOpenConfirmMode?
    @Published var keepOpenChecked: Set<String> = []
    /// On-screen apps the next role doesn't need (PRD V10 Change 1). Ticked =
    /// keep open; all start unticked, and unticked apps quit.
    @Published var switchRows: [KeepOpenPanelHelper.Row] = []

    @Published var quitRows: [KeepOpenPanelHelper.Row] = []
    @Published var quitChecked: Set<String> = []

    @Published var terminalBlockProfileID: UUID?
    private var terminalRunAnywayProfileIDs: Set<UUID> = []
    /// When "End session" was clicked on a check-in. The session's recorded
    /// time stops here if the end is confirmed; Cancel clears it (PRD V7 Change 6).
    var endRequestedAt: Date?
    /// Timer chosen on a card's chips, applied when that role starts.
    var pendingStartTimerMinutes: Int?

    /// The profile being built or edited. Nothing here reaches disk until Save,
    /// and it lives on the model rather than in view state so it survives the
    /// panel being torn down by a system picker.
    @Published var draft: Profile?
    @Published var draftIsNew = false
    @Published var draftNameError: String?
    @Published var addMode: AddMode = .none
    @Published var flashedItemID: UUID?

    @Published var newProfileName = ""
    @Published var newProfileError: String?
    @Published var newProfileColor: ProfileColor = .navy

    @Published var linkURLText = ""
    @Published var linkTitleText = ""
    @Published var linkError: String?

    /// Draft for the Claude destination field. Lives on the model so it
    /// survives the panel being torn down by a system picker.
    @Published var destinationEditingItemID: UUID?
    @Published var destinationPasteText = ""
    @Published var destinationError: String?
    @Published var chromeEditingItemID: UUID?

    @Published var appQuery = ""
    @Published var appHighlightIndex = 0
    @Published var installedApps: [InstalledApp] = []
    private var isLoadingApps = false

    /// What happened the last time Mevin tried to list Chrome's profiles. Held so
    /// the UI can say which of the failures it is rather than guessing.
    @Published var chromeLookup: ChromeProfileLookup = .ok([])
    @Published var chromeDirectoryText = ""
    @Published var chromeLabelText = ""
    @Published var chromeEntryError: String?
    /// Set once the user has launched the Test it check, so the Add button can
    /// stop being the first thing they reach for.
    @Published var chromeDidTest = false
    @Published var chromeDetecting = false
    @Published var chromeDetectStatus: String?
    /// Real Chrome toolbar name captured during Test it, keyed to the pasted directory.
    private var pendingChromeToolbarName: String?
    private var pendingChromeToolbarDirectory: String?
    @Published var folderOpenerMessage: String?

    /// Which profile row the keyboard is on. Lives here with the rest of the UI
    /// state rather than in the view, matching how the builder holds its draft.
    @Published var listHighlight = 0
    /// The one non-active card the user has opened. The active card is always
    /// expanded and is not tracked here.
    @Published var expandedProfileID: UUID?
    /// The card whose trash button was pressed, awaiting confirmation.
    @Published var deletingProfileID: UUID?

    /// Drives the session timer. Derived from `startedAt` on every read rather
    /// than accumulated, so sleeping the laptop or relaunching Mevin cannot make
    /// it drift.
    @Published private(set) var now = Date()
    private var tickTask: Task<Void, Never>?

    @Published var isEnding = false
    @Published var startReport: StartReport?
    @Published var pendingStartProfileID: UUID?
    /// Proposal after End session writes through to the profile and returns to
    /// the list. The builder path still waits for Save.
    @Published var proposalFromSessionEnd = false

    @Published var openaiKeyDraft = ""
    @Published var deepseekKeyDraft = ""
    @Published var validatingProvider: AIProvider?
    @Published var proposalItems: [ProposalItem] = []
    @Published var proposalUnmatched: [String] = []
    @Published var screenshotError: String?
    @Published var isReadingScreenshot = false
    @Published var showingScreenshotConsent = false
    @Published var consentDontAskChecked = false
    private var pendingScreenshotJPEG: Data?

    enum AddMode: Equatable {
        case none
        case app
        case chromeProfile
        case link
    }

    /// Bundle IDs the user confirmed on the close list, captured at confirm time
    /// so nothing added afterwards is quit without having been shown.
    private let store: JSONProfileStore
    private let focusTracker = FocusTracker()
    let awakeTracker = AwakeTimeTracker()
    var roleUseStartedAt: Date?
    var checkInAwakeBaseline: TimeInterval = 0
    var checkInUnansweredSince: Date?
    var timerFiredForCurrentSetting = false
    /// Awake seconds into the session when the current timer was set; the
    /// timer runs from here, not from the session start.
    var timerSetAtAwake: TimeInterval = 0
    var sessionLifecycleTask: Task<Void, Never>?
    var checkInAutoEndTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    weak var panel: PanelController?

    init(store: JSONProfileStore = JSONProfileStore()) {
        self.store = store
        load()
    }

    // MARK: - Persistence

    func load() {
        do {
            var file = try store.load()
            // A session still recorded at launch means a crash, a force quit or
            // a shutdown. It isn't resumed; its time is recorded up to the last
            // activity Mevin saw, and the list is offered as normal.
            if let interrupted = file.activeSession {
                if let record = RoleUsageStats.interruptedRecord(interrupted) {
                    file.roleUses.append(record)
                }
                file.activeSession = nil
            }
            profiles = file.profiles
            keepOpenBundleIds = file.keepOpenBundleIds
            if keepOpenBundleIds.isEmpty {
                keepOpenBundleIds = MevinConfig.defaultNeverCloseBundleIds
            }
            snapshots = file.snapshots
            chromeWindowBindings = file.chromeWindowBindings
            roleUses = file.roleUses
            checkInIntervalHours = file.checkInIntervalHours
            activeSession = nil
            try store.save(currentFile)
        } catch {
            profiles = []
            keepOpenBundleIds = []
            snapshots = []
            chromeWindowBindings = [:]
            activeSession = nil
        }
    }

    private var currentFile: StoreFile {
        StoreFile(
            version: JSONProfileStore.currentVersion,
            profiles: profiles,
            activeSession: activeSession,
            keepOpenBundleIds: keepOpenBundleIds,
            snapshots: snapshots,
            chromeWindowBindings: chromeWindowBindings,
            roleUses: roleUses,
            checkInIntervalHours: checkInIntervalHours
        )
    }

    func persist() {
        try? store.save(currentFile)
    }

    // MARK: - Lookups

    var activeProfile: Profile? {
        guard let id = activeSession?.profileId else { return nil }
        return profiles.first { $0.id == id }
    }

    func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    func isRunning(_ profileID: UUID) -> Bool {
        activeSession?.profileId == profileID
    }

    /// The list under the active section: every profile except the active
    /// one, which has its own section while it runs (PRD V8 Change 6).
    var listProfiles: [Profile] {
        guard let activeID = activeSession?.profileId else { return profiles }
        return profiles.filter { $0.id != activeID }
    }

    /// One card at most is expanded (PRD V8 Change 5).
    func isExpanded(_ profileID: UUID) -> Bool {
        expandedProfileID == profileID
    }

    /// Clicking a card toggles it; expanding one collapses any other.
    func cardTapped(profileID: UUID) {
        expandedProfileID = expandedProfileID == profileID ? nil : profileID
        if let index = listProfiles.firstIndex(where: { $0.id == profileID }) {
            listHighlight = index
        }
    }

    func nameIsTaken(_ raw: String, excluding id: UUID?) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return false }
        return profiles.contains { $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }
    }

    // MARK: - Navigation

    func showList() {
        screen = .list
    }

    func startNewProfile() {
        newProfileName = ""
        newProfileError = nil
        // Preselect a colour nobody is using, so two profiles only match when
        // the user chooses it.
        newProfileColor = ProfileColor.firstUnused(in: profiles)
        screen = .newProfile
    }

    /// Creates the profile in memory only. It reaches disk on Save.
    func continueFromName() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if nameIsTaken(name, excluding: nil) {
            newProfileError = "You already have a profile with this name."
            return
        }
        newProfileError = nil
        draft = Profile(name: name, colorId: newProfileColor.rawValue)
        draftIsNew = true
        resetBuilderState()
        screen = .builder
    }

    func editProfile(id: UUID) {
        guard let profile = profile(id: id) else { return }
        draft = profile
        draftIsNew = false
        resetBuilderState()
        screen = .builder
    }

    func closeBuilder() {
        draft = nil
        draftIsNew = false
        resetBuilderState()
        screen = .list
    }

    private func resetBuilderState() {
        addMode = .none
        draftNameError = nil
        linkURLText = ""
        linkTitleText = ""
        linkError = nil
        appQuery = ""
        appHighlightIndex = 0
        chromeDirectoryText = ""
        chromeLabelText = ""
        chromeEntryError = nil
        chromeDidTest = false
        destinationEditingItemID = nil
        destinationPasteText = ""
        destinationError = nil
        screenshotError = nil
        isReadingScreenshot = false
        showingScreenshotConsent = false
        consentDontAskChecked = false
        pendingScreenshotJPEG = nil
        proposalItems = []
        proposalUnmatched = []
    }

    /// Escape backs out one level; the panel closes only when there is nothing
    /// left to back out of. Returns true when the model handled the key.
    func escapePressed() -> Bool {
        if deletingProfileID != nil {
            deletingProfileID = nil
            return true
        }
        if screen == .list, expandedProfileID != nil {
            expandedProfileID = nil
            return true
        }
        if showingScreenshotConsent {
            cancelScreenshotConsent()
            return true
        }
        if addMode != .none {
            addMode = .none
            return true
        }
        if destinationEditingItemID != nil {
            cancelDestinationEdit()
            return true
        }
        switch screen {
        case .keepOpenConfirm:
            cancelKeepOpenPanel()
            return true
        case .quitConfirm:
            cancelQuitAllTabs()
            return true
        case .proposal:
            cancelProposal()
            return true
        case .builder:
            closeBuilder()
            return true
        case .newProfile, .keepOpen, .aiSettings, .settings:
            screen = .list
            return true
        case .list:
            return false
        }
    }

    func panelDidClose() {
        // A draft is deliberately kept: reopening returns to the builder with
        // unsaved work intact, which is what the picker flows depend on.
        if addMode == .app || addMode == .chromeProfile {
            addMode = .none
        }
        chromeEditingItemID = nil
        stopTicking()
    }

    func panelDidOpen() {
        accessibilityOff = !AccessibilityWindowControl.isTrusted()
        startTickingIfNeeded()
    }

    /// V11 Change 1: System Settings > Privacy & Security > Accessibility.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Session timer

    /// There is no reason to run a one-second tick against a window nobody is
    /// looking at, so the timer only runs while the panel is visible. The elapsed
    /// value is recomputed from `startedAt` when it reopens, so nothing is lost.
    private func startTickingIfNeeded() {
        stopTicking()
        guard activeSession != nil else { return }
        now = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.now = Date()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// The active section's clock (PRD V8 Change 6): time left with a timer
    /// (00:00 once it ends, until the notification is answered), otherwise
    /// elapsed session time. Awake time only, so it matches the V7 stats.
    /// Reads `now` so it refreshes on the panel's one-second tick.
    var activeClockText: String {
        _ = now
        guard activeSession != nil else { return SessionClock.clockText(seconds: 0) }
        return SessionClock.clockText(seconds: timerRemainingSeconds ?? awakeTracker.elapsed())
    }

    // MARK: - Builder edits

    func renameDraft(_ raw: String) {
        guard var current = draft else { return }
        current.name = raw
        draft = current
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftNameError = nil
        } else if nameIsTaken(trimmed, excluding: draftIsNew ? nil : current.id) {
            draftNameError = "You already have a profile with this name."
        } else {
            draftNameError = nil
        }
    }

    func setDraftColor(_ color: ProfileColor) {
        guard var current = draft else { return }
        current.colorId = color.rawValue
        draft = current
    }

    var draftNameIsValid: Bool {
        guard let draft else { return false }
        return draft.hasNameWorthKeeping && draftNameError == nil
    }

    var draftChromeIsValid: Bool {
        guard let draft else { return true }
        if !draft.includesChrome { return true }
        return draft.chromeIsLinked
    }

    /// An empty profile can't be saved; deleting lives in the menu (owner
    /// decision, 19 Oct 2026, with PRD V8 Change 7).
    var draftHasItems: Bool {
        !(draft?.items.isEmpty ?? true)
    }

    var draftSaveIsValid: Bool {
        draftNameIsValid && draftChromeIsValid && draftHasItems
    }

    func addApp(bundleId: String, name: String) {
        if Constants.chromeBundleIDs.contains(bundleId) {
            ensureChromeProfileItem()
            addMode = .none
            appQuery = ""
            appHighlightIndex = 0
            return
        }
        guard var current = draft else { return }
        if let existing = current.items.first(where: { $0.type == .app && $0.bundleId == bundleId }) {
            flash(existing.id)
            addMode = .none
            return
        }
        let item = ProfileItem.app(bundleId: bundleId, name: name)
        current.items.append(item)
        draft = current
        flash(item.id)
        addMode = .none
        appQuery = ""
        appHighlightIndex = 0
    }

    func addChromeProfile(_ account: ChromeAccount) {
        guard var current = draft else { return }
        // Exactly one Chrome profile per profile, so a new choice replaces it.
        current.items.removeAll { $0.type == .chromeProfile }
        current.items.removeAll { item in
            item.type == .app && item.bundleId.map { Constants.chromeBundleIDs.contains($0) } == true
        }
        var item = ProfileItem.chromeProfile(directory: account.directory, displayName: account.displayName)
        ChromeDebugLog.log("addChromeProfile: directory=\"\(account.directory)\" displayName=\"\(account.displayName)\" account.toolbar=\(account.chromeToolbarName ?? "nil") pending=\(pendingChromeToolbarName ?? "nil") pendingDir=\(pendingChromeToolbarDirectory ?? "nil")")  // DEBUG-CHROME-LOG
        // Only store Chrome's real toolbar name — never seed from the Mevin label.
        if let pending = pendingChromeToolbarName,
           pendingChromeToolbarDirectory == account.directory,
           !pending.isEmpty {
            item.chromeToolbarName = pending
        } else if let toolbar = account.chromeToolbarName, !toolbar.isEmpty,
                  toolbar.localizedCaseInsensitiveCompare(account.displayName) != .orderedSame {
            item.chromeToolbarName = toolbar
        } else {
            item.chromeToolbarName = nil
        }
        ChromeDebugLog.log("addChromeProfile: stored chromeToolbarName=\(item.chromeToolbarName ?? "nil")")  // DEBUG-CHROME-LOG
        current.items.append(item)
        draft = current
        flash(item.id)
        addMode = .none
        chromeEditingItemID = nil
        chromeDirectoryText = ""
        chromeLabelText = ""
        chromeEntryError = nil
        chromeDidTest = false
        pendingChromeToolbarName = nil
        pendingChromeToolbarDirectory = nil
    }

    /// One chromeProfile row per role; plain Chrome app rows are folded into it.
    func ensureChromeProfileItem() {
        guard var current = draft else { return }
        current.items.removeAll { item in
            item.type == .app && item.bundleId.map { Constants.chromeBundleIDs.contains($0) } == true
        }
        if current.items.contains(where: { $0.type == .chromeProfile }) {
            draft = current
            if let chrome = current.items.first(where: { $0.type == .chromeProfile }) {
                flash(chrome.id)
            }
            return
        }
        let item = ProfileItem.unlinkedChrome()
        current.items.append(item)
        draft = current
        flash(item.id)
    }

    func beginChromeEdit(itemID: UUID) {
        chromeEditingItemID = itemID
        loadChromeProfiles()
        if let chrome = draft?.items.first(where: { $0.id == itemID }), chrome.isChromeLinked {
            chromeDirectoryText = chrome.directory ?? ""
            chromeLabelText = chrome.displayName ?? ""
        } else {
            chromeDirectoryText = ""
            chromeLabelText = ""
        }
        chromeEntryError = nil
        chromeDidTest = false
    }

    func cancelChromeEdit() {
        chromeEditingItemID = nil
        chromeDirectoryText = ""
        chromeLabelText = ""
        chromeEntryError = nil
        chromeDidTest = false
        pendingChromeToolbarName = nil
        pendingChromeToolbarDirectory = nil
    }

    /// Profiles linked on other roles, for one-tap reuse in the Chrome panel.
    func chromeProfilesUsedElsewhere() -> [ChromeAccount] {
        guard let draft else { return [] }
        var seen = Set<String>()
        var accounts: [ChromeAccount] = []
        for profile in profiles where profile.id != draft.id {
            guard let chrome = profile.chromeProfile, chrome.isChromeLinked,
                  let directory = chrome.directory else { continue }
            guard seen.insert(directory).inserted else { continue }
            accounts.append(
                ChromeAccount(
                    directory: directory,
                    displayName: chrome.displayName ?? directory,
                    chromeToolbarName: chrome.chromeToolbarName
                )
            )
        }
        return accounts.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func chromeProfileSharedWithOtherRoles(directory: String) -> Bool {
        guard let draft else { return false }
        return profiles.contains { profile in
            profile.id != draft.id && profile.chromeProfile?.directory == directory
        }
    }

    // MARK: - Chrome profile, entered by hand

    /// The folder name Chrome needs, derived from whatever the user pasted.
    var chromeDirectoryFromEntry: String? {
        ChromeService.profileDirectoryName(fromPasted: chromeDirectoryText)
    }

    func chromeManualEntryDidEditPath() {
        chromeEntryError = nil
        chromeDidTest = false
        pendingChromeToolbarName = nil
        pendingChromeToolbarDirectory = nil
    }

    /// Puts `chrome://version` on the clipboard. Mevin no longer opens it: it
    /// would land in whichever profile Chrome used last (PRD V10 Change 6).
    func copyChromeVersionAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("chrome://version", forType: .string)
    }

    /// Launches the entered profile so the user can confirm with their own eyes
    /// that it lands in the right place. Uses the same open/reuse path as Start.
    func testChromeProfileEntry() {
        guard let directory = chromeDirectoryFromEntry else {
            chromeEntryError = "Paste the Profile Path from chrome://version, or the folder name itself."
            return
        }
        guard let draft else { return }
        chromeEntryError = nil
        chromeDidTest = true
        let profileId = draft.id
        ChromeDebugLog.log("==== testChromeProfileEntry: pasted=\"\(chromeDirectoryText)\" -> directory=\"\(directory)\" typedName=\"\(chromeLabelText)\"")  // DEBUG-CHROME-LOG
        let toolbarHint: String? = {
            if let chrome = draft.chromeProfile, chrome.directory == directory {
                return chrome.chromeToolbarName
            }
            if pendingChromeToolbarDirectory == directory {
                return pendingChromeToolbarName
            }
            return nil
        }()
        Task {
            var bindings = chromeWindowBindings
            let result = await ChromeWindowService.openOrReuseProfileWindow(
                profileId: profileId,
                directory: directory,
                urls: [],
                chromeProfileName: toolbarHint,
                bindings: &bindings,
                captureProfileName: { [weak self] name in
                    guard let self else { return }
                    self.pendingChromeToolbarDirectory = directory
                    self.pendingChromeToolbarName = name
                    if var current = self.draft,
                       let index = current.items.firstIndex(where: {
                           $0.type == .chromeProfile && $0.directory == directory
                       }) {
                        current.items[index].chromeToolbarName = name
                        self.draft = current
                    }
                }
            )
            chromeWindowBindings = bindings
            persist()
            if !result.success {
                chromeEntryError = "Couldn’t open Chrome."
            }
        }
    }

    func addChromeProfileFromEntry() {
        guard let directory = chromeDirectoryFromEntry else {
            chromeEntryError = "Paste the Profile Path from chrome://version, or the folder name itself."
            return
        }
        let typed = chromeLabelText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Falling back to the folder name is honest: it is what the user gave us.
        // The PRD's "never show Profile 3" is satisfied whenever they name it.
        addChromeProfile(
            ChromeAccount(directory: directory, displayName: typed.isEmpty ? directory : typed)
        )
    }

    func addLinkFromDraftFields() {
        guard var current = draft else { return }
        guard let url = ProfileItem.normalizedURL(linkURLText) else {
            linkError = "That doesn’t look like a web address."
            return
        }
        let typed = linkTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = typed.isEmpty ? (ProfileItem.host(of: url) ?? url) : typed
        let item = ProfileItem.link(url: url, title: title)
        current.items.append(item)
        draft = current
        flash(item.id)
        // Fields stay open so several links can be pasted in a row.
        linkURLText = ""
        linkTitleText = ""
        linkError = nil
    }

    func addLink(url: String, title: String) {
        guard var current = draft else { return }
        if let existing = current.items.first(where: { $0.type == .link && $0.url == url }) {
            flash(existing.id)
            return
        }
        let item = ProfileItem.link(url: url, title: title)
        current.items.append(item)
        draft = current
        flash(item.id)
    }

    func addFolder(path: String) {
        guard var current = draft else { return }
        if let existing = current.items.first(where: { $0.type == .folder && $0.path == path }) {
            flash(existing.id)
            return
        }
        let item = ProfileItem.folder(path: path)
        current.items.append(item)
        draft = current
        flash(item.id)
    }

    func setFolderOpener(itemID: UUID, app: InstalledApp?) {
        if app?.bundleId == Constants.terminalBundleID {
            folderOpenerMessage = "To run Terminal in a folder, add a tab on the Terminal row."
            return
        }
        folderOpenerMessage = nil
        guard var current = draft,
              let idx = current.items.firstIndex(where: { $0.id == itemID }) else { return }
        current.items[idx].appBundleId = app?.bundleId
        current.items[idx].appName = app?.name
        draft = current
    }

    // MARK: - Terminal tabs (PRD V5)

    func addTerminalTab(itemID: UUID) {
        guard var current = draft,
              let idx = current.items.firstIndex(where: { $0.id == itemID }) else { return }
        var tabs = current.items[idx].terminalTabs ?? []
        tabs.append(TerminalTab())
        current.items[idx].terminalTabs = tabs
        draft = current
        flash(itemID)
    }

    func removeTerminalTab(itemID: UUID, tabID: UUID) {
        guard var current = draft,
              let idx = current.items.firstIndex(where: { $0.id == itemID }) else { return }
        var tabs = current.items[idx].terminalTabs ?? []
        tabs.removeAll { $0.id == tabID }
        current.items[idx].terminalTabs = tabs.isEmpty ? nil : tabs
        draft = current
        flash(itemID)
    }

    func setTerminalTabPath(itemID: UUID, tabID: UUID, path: String?) {
        guard var current = draft,
              let idx = current.items.firstIndex(where: { $0.id == itemID }),
              let tabIndex = current.items[idx].terminalTabs?.firstIndex(where: { $0.id == tabID })
        else { return }
        current.items[idx].terminalTabs?[tabIndex].path = path
        draft = current
    }

    func setTerminalTabCommand(itemID: UUID, tabID: UUID, command: String) {
        guard var current = draft,
              let idx = current.items.firstIndex(where: { $0.id == itemID }),
              let tabIndex = current.items[idx].terminalTabs?.firstIndex(where: { $0.id == tabID })
        else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        current.items[idx].terminalTabs?[tabIndex].command = trimmed.isEmpty ? nil : trimmed
        draft = current
    }

    func terminalTabCommand(itemID: UUID, tabID: UUID) -> String {
        draft?.items.first(where: { $0.id == itemID })?
            .terminalTabs?.first(where: { $0.id == tabID })?.command ?? ""
    }

    func browseForTerminalTabFolder(itemID: UUID, tabID: UUID) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose a folder for this tab"
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url else { return }
            self.setTerminalTabPath(itemID: itemID, tabID: tabID, path: url.path)
        }
    }

    // MARK: - App destinations

    var destinationPasteIsValid: Bool {
        guard let item = editingDestinationItem else { return false }
        return parsedDestination(for: item) != nil
    }

    func beginDestinationEdit(itemID: UUID) {
        destinationEditingItemID = itemID
        if let destination = draft?.items.first(where: { $0.id == itemID })?.destination {
            destinationPasteText = destination.httpsURL
        } else {
            destinationPasteText = ""
        }
        destinationError = nil
    }

    func updateDestinationPaste() {
        guard let item = editingDestinationItem else {
            destinationError = nil
            return
        }
        destinationError = destinationParseError(for: item)
    }

    func addDestination(itemID: UUID) {
        guard var current = draft,
              let index = current.items.firstIndex(where: { $0.id == itemID }),
              let parsed = parsedDestination(for: current.items[index])
        else { return }

        current.items[index].destination = parsed
        draft = current
        destinationEditingItemID = nil
        destinationPasteText = ""
        destinationError = nil
        flash(itemID)
    }

    func cancelDestinationEdit() {
        destinationEditingItemID = nil
        destinationPasteText = ""
        destinationError = nil
    }

    private var editingDestinationItem: ProfileItem? {
        guard let id = destinationEditingItemID else { return nil }
        return draft?.items.first(where: { $0.id == id })
    }

    private func parsedDestination(for item: ProfileItem) -> ItemDestination? {
        switch item.bundleId {
        case Constants.figmaBundleID:
            guard case .success(let parsed) = FigmaService.parse(destinationPasteText) else { return nil }
            return .figma(kind: parsed.kind, fileKey: parsed.fileKey, slug: parsed.slug, nodeId: parsed.nodeId)
        case Constants.claudeBundleID:
            guard case .success(let parsed) = ClaudeService.parse(destinationPasteText) else { return nil }
            return .claude(kind: parsed.kind, id: parsed.id)
        case Constants.slackBundleID:
            guard case .success(let parsed) = SlackService.parse(destinationPasteText) else { return nil }
            return .slack(team: parsed.team, channel: parsed.channel)
        default:
            return nil
        }
    }

    private func destinationParseError(for item: ProfileItem) -> String? {
        switch item.bundleId {
        case Constants.figmaBundleID:
            if case .failure(let error) = FigmaService.parse(destinationPasteText) { return error.message }
            return nil
        case Constants.claudeBundleID:
            if case .failure(let error) = ClaudeService.parse(destinationPasteText) { return error.message }
            return nil
        case Constants.slackBundleID:
            if case .failure(let error) = SlackService.parse(destinationPasteText) { return error.message }
            return nil
        default:
            return nil
        }
    }

    func clearDestination(itemID: UUID) {
        guard var current = draft,
              let index = current.items.firstIndex(where: { $0.id == itemID }) else { return }
        current.items[index].destination = nil
        draft = current
        if destinationEditingItemID == itemID {
            cancelDestinationEdit()
        }
    }

    func removeItem(id: UUID) {
        guard var current = draft else { return }
        current.items.removeAll { $0.id == id }
        draft = current
        if destinationEditingItemID == id {
            cancelDestinationEdit()
        }
    }

    /// Reorders one item onto another's position. Only items of the same kind can
    /// trade places, since order within a group is the only thing that means
    /// anything: apps launch in their own order, links become tabs in theirs.
    func moveItem(draggedID: UUID, onto targetID: UUID) {
        guard var current = draft,
              draggedID != targetID,
              let dragged = current.items.first(where: { $0.id == draggedID }),
              let target = current.items.first(where: { $0.id == targetID }),
              dragged.type == target.type else { return }

        let slots = current.items.indices.filter { current.items[$0].type == dragged.type }
        var ordered = slots.map { current.items[$0] }
        guard let from = ordered.firstIndex(where: { $0.id == draggedID }),
              let to = ordered.firstIndex(where: { $0.id == targetID }) else { return }

        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: to)
        for (position, index) in slots.enumerated() {
            current.items[index] = ordered[position]
        }
        draft = current
    }

    func moveGroup(_ group: ItemGroup, by offset: Int) {
        guard var current = draft,
              let index = current.groupOrder.firstIndex(of: group) else { return }
        let target = index + offset
        guard target >= 0, target < current.groupOrder.count else { return }
        current.groupOrder.swapAt(index, target)
        draft = current
    }

    private func flash(_ id: UUID) {
        flashedItemID = id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.flashedItemID == id else { return }
            self.flashedItemID = nil
        }
    }

    // MARK: - Saving and deleting

    func saveDraft() {
        guard let draft, draftSaveIsValid else { return }
        commit(draft)
        closeBuilder()
    }

    private func commit(_ profile: Profile) {
        var cleaned = profile
        cleaned.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.groupOrder = Profile.normalized(cleaned.groupOrder)
        cleaned.terminalCommandsFingerprint = TerminalCommandFingerprint.compute(for: cleaned)
        if let idx = profiles.firstIndex(where: { $0.id == cleaned.id }) {
            profiles[idx] = cleaned
        } else {
            profiles.append(cleaned)
        }
        persist()
    }

    /// Menu → Delete a profile… → this profile. The active role can't be
    /// deleted until its session ends (PRD V8 Change 7).
    func requestDelete(profileID: UUID) {
        guard !isRunning(profileID), profile(id: profileID) != nil else { return }
        screen = .list
        deletingProfileID = profileID
    }

    func cancelDelete() {
        deletingProfileID = nil
    }

    /// Removes the profile with its apps, links, Terminal tabs and history
    /// (stats, save points, Chrome window bindings).
    func confirmDelete() {
        guard let id = deletingProfileID, !isRunning(id) else { return }
        deletingProfileID = nil
        if expandedProfileID == id { expandedProfileID = nil }
        profiles.removeAll { $0.id == id }
        roleUses.removeAll { $0.profileId == id }
        snapshots.removeAll { $0.profileId == id }
        let marker = id.uuidString.uppercased()
        chromeWindowBindings = chromeWindowBindings.filter { !$0.key.contains(marker) }
        listHighlight = min(listHighlight, max(0, listProfiles.count - 1))
        persist()
    }

    func removeFailedItem(profileID: UUID, itemID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].items.removeAll { $0.id == itemID }
        persist()
        startReport?.failures.removeAll { $0.id == itemID }
        if startReport?.failures.isEmpty == true {
            startReport = nil
        }
    }

    func dismissStartReport() {
        startReport = nil
    }

    // MARK: - Running a profile

    /// Start, or end, or hand over. Which of the three it is depends only on what
    /// is already running, so the card's Start session and the Return key can
    /// both come through here.
    /// Card timer chips: start (or switch to) the role with this timer, in one
    /// click (PRD V8 Change 5). Dropped if the start is cancelled.
    func startSession(profileID: UUID, timerMinutes: Int) {
        pendingStartTimerMinutes = timerMinutes
        expandedProfileID = nil
        startOrEndSession(profileID: profileID)
    }

    func startOrEndSession(profileID: UUID) {
        if isRunning(profileID) {
            beginEndFlow()
            return
        }
        // Checked before the Keep open? panel, so a blocked start never
        // minimizes anything or ends the current role half-way (PRD V6 5.3).
        if let profile = profile(id: profileID), terminalCommandsBlocked(profile) {
            terminalBlockProfileID = profileID
            screen = .list
            panel?.show()
            return
        }
        if activeSession != nil {
            switchTo(profileID: profileID)
            return
        }
        launch(profileID: profileID)
    }

    private func switchTo(profileID: UUID) {
        guard let outgoing = activeProfile else { return }
        writeSnapshot(for: outgoing)
        pendingStartProfileID = profileID
        showPanelOrProceed(mode: .switching(toProfileId: profileID))
    }

    private func launch(profileID: UUID) {
        guard profile(id: profileID) != nil else { return }
        pendingStartProfileID = profileID
        showPanelOrProceed(mode: .starting(profileId: profileID))
    }

    /// Nothing to review means no panel: start or switch in one click
    /// (PRD V10 Change 1).
    private func showPanelOrProceed(mode: KeepOpenConfirmMode) {
        populateKeepOpenPanel(mode: mode)
        if switchRows.isEmpty {
            confirmKeepOpenPanel()
            return
        }
        screen = .keepOpenConfirm
        panel?.show()
    }

    /// `outgoing` is the role being switched away from: its context in the
    /// apps both roles use is closed once the new one is open (PRD V10 Change 2).
    private func start(
        profileID: UUID,
        carriedOver: Set<String> = [],
        outgoing: Profile? = nil
    ) async {
        guard let profile = profile(id: profileID) else { return }

        startReport = nil
        terminalBlockProfileID = nil

        if terminalCommandsBlocked(profile) {
            terminalBlockProfileID = profile.id
            panel?.show()
            return
        }

        activeTimerMinutes = pendingStartTimerMinutes ?? profile.defaultTimerMinutes
        pendingStartTimerMinutes = nil
        expandedProfileID = nil
        activeSession = ActiveSession(
            profileId: profile.id,
            startedAt: Date(),
            baselineBundleIds: [],
            focusSeconds: [:],
            carriedOverBundleIds: Array(carriedOver)
        )
        persist()
        panel?.refreshStatusIcon()
        startCapture()
        beginSessionLifecycle(for: profile)

        var failures: [StartReport.Failure] = []

        for group in profile.groupOrder {
            switch group {
            case .chromeWithLinks:
                failures.append(contentsOf: await openChrome(for: profile, carriedOver: carriedOver, outgoing: outgoing))
            case .apps:
                for item in profile.items(in: .apps) {
                    guard let bundleId = item.bundleId else { continue }
                    // Terminal with tabs brings up its own window; making Terminal
                    // visible first would add an empty default window beside it.
                    // A kept Terminal still gets the role's own tabs alongside
                    // its windows (PRD V6 Change 3 table, kept by V9).
                    if bundleId == Constants.terminalBundleID,
                       let tabs = item.terminalTabs,
                       !tabs.isEmpty {
                        let tabFailures = await TerminalStartupService.reuseOrRunTabs(
                            roleName: profile.name,
                            profileId: profile.id,
                            tabs: tabs
                        )
                        for label in tabFailures {
                            failures.append(.init(id: item.id, label: label, removable: false))
                        }
                        continue
                    }
                    if carriedOver.contains(bundleId) { continue }
                    if let miss = await LaunchService.ensureRoleAppVisible(bundleId: bundleId) {
                        failures.append(.init(id: item.id, label: StartReport.bringUpLabel(miss)))
                        continue
                    }
                    if let destination = SessionCapture.overlayDestination(
                        item: item,
                        snapshot: SessionCapture.latest(snapshots, for: profile.id)
                    ) {
                        if let miss = openDestination(destination, for: item) {
                            failures.append(.init(id: item.id, label: StartReport.bringUpLabel(miss)))
                        }
                    }
                }
            case .folders:
                for item in profile.items(in: .folders) {
                    guard let path = item.path else { continue }
                    if let miss = await LaunchService.openFolder(path, appBundleId: item.appBundleId) {
                        failures.append(.init(id: item.id, label: StartReport.bringUpLabel(miss)))
                    }
                }
            }
        }

        try? await Task.sleep(for: .seconds(2))

        for bundleId in profile.roleSurfaceBundleIdsInOrder() {
            if carriedOver.contains(bundleId) { continue }
            let stillHidden: Bool
            if let app = WindowService.runningApplication(bundleId: bundleId) {
                stillHidden = !AccessibilityWindowControl.hasOnScreenNormalWindow(for: app.processIdentifier)
            } else {
                stillHidden = true
            }
            guard stillHidden else { continue }
            let label = StartReport.bringUpLabel(LaunchService.displayName(bundleId: bundleId))
            guard !failures.contains(where: { $0.label == label }) else { continue }
            // Tie the line to the item it came from, so Remove can act on it.
            let itemID = profile.items.first { $0.bundleId == bundleId || $0.closeBundleId == bundleId }?.id
            failures.append(.init(id: itemID ?? UUID(), label: label, removable: itemID != nil))
        }

        if let first = profile.roleSurfaceBundleIdsInOrder().first {
            _ = LaunchService.activate(bundleId: first)
        }

        if failures.isEmpty {
            startReport = nil
        } else {
            startReport = StartReport(profileId: profile.id, failures: failures)
        }
    }

    /// Opens an app destination. Desktop when that app is installed, otherwise
    /// the https address rides with Chrome. Returns a label when nothing could
    /// be opened.
    private func openDestination(
        _ destination: ItemDestination,
        for item: ProfileItem
    ) -> String? {
        if destination.isDesktopInstalled {
            switch destination {
            case .claude:
                guard let url = destination.desktopURL, ClaudeService.open(url) else {
                    return item.label
                }
            case .figma:
                guard let url = destination.desktopURL, FigmaService.open(url) else {
                    return item.label
                }
            case .slack:
                guard let url = destination.desktopURL, SlackService.open(url) else {
                    return item.label
                }
            }
            return nil
        }
        if ChromeService.isInstalled() {
            // The https address is included in the Chrome launch for this profile.
            return nil
        }
        return item.label
    }

    /// One Chrome launch carries the profile directory and every link, which
    /// yields a single window with the tabs in order instead of a race between
    /// the browser starting and URLs arriving.
    private func openChrome(for profile: Profile, carriedOver: Set<String>, outgoing: Profile?) async -> [StartReport.Failure] {
        // Destinations join this launch only when that app's desktop client is
        // missing; otherwise they are opened as claude:// / figma:// URLs in
        // the apps group.
        let urls = profile.links.compactMap(\.url) + profile.browserDestinationURLs
        let chrome = profile.chromeProfile

        guard profile.includesChrome || !urls.isEmpty else { return [] }

        guard ChromeService.isInstalled() else {
            let id = chrome?.id ?? profile.links.first?.id ?? profile.id
            return [.init(id: id, label: StartReport.bringUpLabel("Google Chrome"))]
        }

        if profile.includesChrome, let chrome, !chrome.isChromeLinked {
            return [.init(id: chrome.id, label: StartReport.bringUpLabel("Google Chrome (no profile linked)"))]
        }

        if let chrome {
            guard let directory = chrome.directory, !directory.isEmpty else {
                return [.init(id: chrome.id, label: StartReport.bringUpLabel("Google Chrome (no profile linked)"))]
            }
            ChromeDebugLog.log("==== openChrome: role \"\(profile.name)\" item directory=\"\(directory)\" displayName=\"\(chrome.displayName ?? "nil")\" chromeToolbarName=\(chrome.chromeToolbarName.map { "\"\($0)\"" } ?? "nil") carriedOver=\(carriedOver)")  // DEBUG-CHROME-LOG
            var bindings = chromeWindowBindings
            var failures: [StartReport.Failure] = []
            let result = await ChromeWindowService.openOrReuseProfileWindow(
                profileId: profile.id,
                directory: directory,
                urls: urls,
                chromeProfileName: chrome.chromeToolbarName,
                bindings: &bindings,
                captureProfileName: { [weak self] name in
                    self?.persistChromeToolbarName(name, itemID: chrome.id, profileID: profile.id)
                }
            )
            if result.success {
                retireOutgoingChromeWindows(outgoing, newDirectory: directory, newRole: profile, bindings: &bindings)
            }
            chromeWindowBindings = bindings
            persist()
            ChromeDebugLog.log("openChrome: result success=\(result.success) warning=\(result.weakReuseWarning ?? "none"); bindings now \(bindings)")  // DEBUG-CHROME-LOG
            if let warning = result.weakReuseWarning {
                failures.append(.init(id: chrome.id, label: warning, removable: false))
            }
            if !result.success {
                failures.append(.init(id: chrome.id, label: StartReport.bringUpLabel(chrome.label)))
            }
            return failures
        }

        // Links without a Chrome profile go to whichever profile Chrome used last.
        ChromeDebugLog.log("openChrome: role has links but NO chrome item; lastUsedDirectory=\(ChromeService.lastUsedDirectory() ?? "unreadable, using Default")")  // DEBUG-CHROME-LOG
        let directory = ChromeService.lastUsedDirectory() ?? "Default"
        _ = ChromeService.openProfile(directory: directory, urls: urls)
        return []
    }

    /// The old role's Chrome profile windows close (or minimize, per decision 4)
    /// once the new role's window is open, only when both roles have a linked
    /// profile and the folders differ (PRD V10 Change 2, V11 Change 2).
    private func retireOutgoingChromeWindows(
        _ outgoing: Profile?,
        newDirectory: String,
        newRole: Profile,
        bindings: inout [String: Int]
    ) {
        guard let outgoing,
              let old = outgoing.chromeProfile, old.isChromeLinked,
              let oldDirectory = old.directory, !oldDirectory.isEmpty,
              oldDirectory != newDirectory
        else { return }
        let oldKey = ChromeWindowService.bindingKey(profileId: outgoing.id, directory: oldDirectory)
        let newKey = ChromeWindowService.bindingKey(profileId: newRole.id, directory: newDirectory)
        let action = MevinConfig.chromeOldWindowAction
        let acted = ChromeWindowService.retireOldProfileWindows(
            oldName: old.chromeToolbarName,
            oldBound: bindings[oldKey],
            newName: newRole.chromeProfile?.chromeToolbarName,
            keep: bindings[newKey],
            action: action
        )
        // A minimized window is still the old role's and is reused next time.
        if action == .close, let bound = bindings[oldKey], acted.contains(bound) {
            bindings[oldKey] = nil
        }
    }

    // MARK: - Keep open

    func showKeepOpen() {
        loadInstalledApps()
        screen = .keepOpen
    }

    func showSettings() {
        screen = .settings
    }

    func showAISettings() {
        screen = .aiSettings
    }

    func isKeptOpen(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return keepOpenBundleIds.contains(bundleId)
    }

    /// This screen has no Save button, so every change writes immediately.
    func addKeepOpen(bundleId: String) {
        guard !keepOpenBundleIds.contains(bundleId) else { return }
        keepOpenBundleIds.append(bundleId)
        persist()
    }

    func removeKeepOpen(bundleId: String) {
        keepOpenBundleIds.removeAll { $0 == bundleId }
        persist()
    }

    /// Resolved for display. An app on the list that has since been uninstalled
    /// still shows, by its identifier, rather than vanishing silently.
    var keepOpenApps: [InstalledApp] {
        keepOpenBundleIds.map { id in
            if let known = installedApps.first(where: { $0.bundleId == id }) { return known }
            return InstalledApp(
                bundleId: id,
                name: LaunchService.displayName(bundleId: id),
                url: LaunchService.applicationURL(bundleId: id) ?? URL(fileURLWithPath: "/")
            )
        }
    }

    func browseForKeepOpenApp() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose an app to keep open"
        openPanel.prompt = "Add app"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.application]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url,
                  let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return }
            self.addKeepOpen(bundleId: bundleId)
        }
    }

    // MARK: - Ending a session

    func beginEndFlow() {
        guard let session = activeSession, let profile = profile(id: session.profileId) else {
            screen = .list
            return
        }
        writeSnapshot(for: profile)
        pendingStartProfileID = nil
        populateKeepOpenPanel(mode: .ending)
        screen = .keepOpenConfirm
    }

    // MARK: - Keep-open confirm (switch + end)

    var keepOpenTitle: String {
        switch keepOpenMode {
        case .starting(let id):
            return "Starting \(profile(id: id)?.name ?? "role")"
        case .switching(let id):
            return "Switching to \(profile(id: id)?.name ?? "role")"
        case .ending:
            return "Ending \(activeProfile?.name ?? "role")"
        case nil:
            return "Keep open?"
        }
    }

    /// The role being started or switched to, for the helper line.
    var keepOpenIncomingName: String {
        switch keepOpenMode {
        case .starting(let id), .switching(let id):
            return profile(id: id)?.name ?? "role"
        case .ending, nil:
            return activeProfile?.name ?? "role"
        }
    }

    var keepOpenPrimaryLabel: String {
        let quitCount = switchRows.filter { !keepOpenChecked.contains($0.bundleId) }.count
        switch keepOpenMode {
        case .starting: return KeepOpenPanelHelper.primaryLabel(quitCount: quitCount, starting: true)
        case .switching: return KeepOpenPanelHelper.primaryLabel(quitCount: quitCount, starting: false)
        case .ending: return "Keep running"
        case nil: return "Continue"
        }
    }

    /// "Quit [Role]'s apps" on the end question (PRD V10 Change 4).
    var endQuitRoleAppsLabel: String {
        "Quit \(activeProfile?.name ?? "role")'s apps"
    }

    func keepOpenBinding(for bundleId: String) -> Binding<Bool> {
        Binding(
            get: { self.keepOpenChecked.contains(bundleId) },
            set: { checked in
                if checked {
                    self.keepOpenChecked.insert(bundleId)
                } else {
                    self.keepOpenChecked.remove(bundleId)
                }
            }
        )
    }

    func quitBinding(for bundleId: String) -> Binding<Bool> {
        Binding(
            get: { self.quitChecked.contains(bundleId) },
            set: { checked in
                if checked {
                    self.quitChecked.insert(bundleId)
                } else {
                    self.quitChecked.remove(bundleId)
                }
            }
        )
    }

    func appIcon(bundleId: String) -> NSImage? {
        LaunchService.applicationURL(bundleId: bundleId).flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func populateKeepOpenPanel(mode: KeepOpenConfirmMode) {
        keepOpenMode = mode
        keepOpenChecked = []
        switch mode {
        case .starting(let id), .switching(let id):
            guard let incoming = profile(id: id) else {
                switchRows = []
                return
            }
            switchRows = KeepOpenPanelHelper.switchRows(
                running: KeepOpenPanelHelper.listedApps(neverClose: Set(keepOpenBundleIds)),
                nextRole: SwitchPlan.ownedBundleIds(in: incoming)
            )
            SwitchDebugLog.logSwitch(roleName: incoming.name, neverClose: Set(keepOpenBundleIds), owned: SwitchPlan.ownedBundleIds(in: incoming), listed: switchRows)  // DEBUG-SWITCH-LOG
        case .ending:
            switchRows = []
        }
    }

    func cancelKeepOpenPanel() {
        guard !isEnding else { return }
        endRequestedAt = nil
        pendingStartTimerMinutes = nil
        pendingStartProfileID = nil
        keepOpenMode = nil
        keepOpenChecked = []
        switchRows = []
        screen = .list
    }

    /// Return on the panel. Unticked rows quit (polite, all at once, no
    /// waiting); ticked rows stay as they are and are carried over into the
    /// next role (PRD V10 Change 1, V6 Change 3).
    func confirmKeepOpenPanel() {
        guard !isEnding else { return }
        let keep = keepOpenChecked.intersection(switchRows.map(\.bundleId))
        let quit = Set(switchRows.map(\.bundleId)).subtracting(keep)

        switch keepOpenMode {
        case .starting(let incomingID), .switching(let incomingID):
            guard profile(id: incomingID) != nil else {
                cancelKeepOpenPanel()
                return
            }
            var outgoing: Profile?
            if case .switching = keepOpenMode {
                outgoing = activeProfile
                finalizeCurrentRoleUse(trimToLastActivity: false)
                cancelSessionLifecycle()
                stopCapture()
            }
            quitPolitely(quit)
            keepOpenMode = nil
            keepOpenChecked = []
            switchRows = []
            screen = .list
            panel?.hide()
            Task { await start(profileID: incomingID, carriedOver: keep, outgoing: outgoing) }

        case .ending:
            endKeepRunning()

        case nil:
            cancelKeepOpenPanel()
        }
    }

    /// Ending, default answer: the role ends and every app stays as it is.
    func endKeepRunning() {
        guard !isEnding, keepOpenMode == .ending else { return }
        Task { await completeEnd(quitApps: []) }
    }

    /// Ends the role and quits every running app listed in it, minimized ones
    /// included (PRD V10 Change 4).
    func endQuitRoleApps() {
        guard !isEnding, keepOpenMode == .ending, let role = activeProfile else { return }
        let apps = KeepOpenPanelHelper.roleApps(
            running: KeepOpenPanelHelper.listedApps(neverClose: Set(keepOpenBundleIds)),
            role: SwitchPlan.ownedBundleIds(in: role)
        )
        Task { await completeEnd(quitApps: apps) }
    }

    /// Ends the role and quits every app on screen on this desktop, relevant
    /// or not. Minimized apps stay running (PRD V10 Change 4).
    func endQuitAllOnScreen() {
        guard !isEnding, keepOpenMode == .ending else { return }
        let rows = KeepOpenPanelHelper.onScreenRows(
            running: KeepOpenPanelHelper.listedApps(neverClose: Set(keepOpenBundleIds))
        )
        Task { await completeEnd(quitApps: Set(rows.map(\.bundleId))) }
    }

    func persistChromeToolbarName(_ name: String, itemID: UUID, profileID: UUID) {
        guard var profile = profile(id: profileID),
              let index = profile.items.firstIndex(where: { $0.id == itemID })
        else { return }
        if profile.items[index].chromeToolbarName == name { return }
        ChromeDebugLog.log("persistChromeToolbarName: role \"\(profile.name)\" chromeToolbarName \(profile.items[index].chromeToolbarName.map { "\"\($0)\"" } ?? "nil") -> \"\(name)\" (SAVED to profiles.json)")  // DEBUG-CHROME-LOG
        profile.items[index].chromeToolbarName = name
        if let pIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[pIndex] = profile
            persist()
        }
    }

    func beginQuitAllTabs() {
        quitRows = KeepOpenPanelHelper.onScreenRows(
            running: KeepOpenPanelHelper.listedApps(neverClose: Set(keepOpenBundleIds))
        )
        quitChecked = Set(quitRows.map(\.bundleId))
        screen = .quitConfirm
    }

    func cancelQuitAllTabs() {
        quitRows = []
        quitChecked = []
        screen = .list
    }

    /// Polite quit, no waiting and no report: an app with unsaved work shows
    /// its own dialog and stays open (PRD V10 section 1, Change 5).
    func confirmQuitAllTabs() {
        quitPolitely(quitChecked)
        quitRows = []
        quitChecked = []
        screen = .list
    }

    func reviewTerminalCommands(for profileID: UUID) {
        terminalBlockProfileID = nil
        pendingStartTimerMinutes = nil
        editProfile(id: profileID)
    }

    func runTerminalAnyway(for profileID: UUID) {
        terminalRunAnywayProfileIDs.insert(profileID)
        terminalBlockProfileID = nil
        // Back through the normal path, so the Keep open? panel still appears.
        startOrEndSession(profileID: profileID)
    }

    private func terminalCommandsBlocked(_ profile: Profile) -> Bool {
        !TerminalCommandFingerprint.matchesStored(profile)
            && !terminalRunAnywayProfileIDs.contains(profile.id)
    }

    func clearSessionHistory() {
        snapshots = []
        roleUses = []
        if var session = activeSession {
            session.focusSeconds = [:]
            activeSession = session
        }
        persist()
    }

    /// Every quit goes through here. Always open wins over every quit rule,
    /// checked against the live list (PRD V11 Change 4).
    private func quitPolitely(_ bundleIds: Set<String>) {
        LaunchService.requestQuit(bundleIds: bundleIds.subtracting(keepOpenBundleIds))
    }

    private func completeEnd(quitApps: Set<String>) async {
        let extras = sessionEndExtras()
        let endedID = activeSession?.profileId
        isEnding = true
        finalizeCurrentRoleUse(trimToLastActivity: false, endAt: endRequestedAt)
        endRequestedAt = nil
        cancelSessionLifecycle()
        stopCapture()

        activeSession = nil
        persist()
        panel?.refreshStatusIcon()

        // Polite quit; Mevin doesn't wait for or report apps that ask to save
        // (PRD V10 section 1).
        quitPolitely(quitApps)

        pendingStartProfileID = nil
        keepOpenMode = nil
        keepOpenChecked = []
        isEnding = false

        if extras.isEmpty {
            screen = .list
        } else if let endedID, let ended = profile(id: endedID) {
            presentSessionExtras(extras, profile: ended)
        } else {
            screen = .list
        }
    }

    // MARK: - Quiet capture

    private func startCapture() {
        focusTracker.start(initial: activeSession?.focusSeconds ?? [:])
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SessionCapture.timerInterval))
                guard let self, !Task.isCancelled, let profile = self.activeProfile else { return }
                self.writeSnapshot(for: profile)
            }
        }
    }

    func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        focusTracker.stop()
    }

    /// Writes the newest snapshot for this profile. Failures in readers stay off
    /// the snapshot rather than blocking the session.
    private func writeSnapshot(for profile: Profile) {
        focusTracker.flush()
        if var session = activeSession {
            session.focusSeconds = focusTracker.seconds
            let lastActive = Date().addingTimeInterval(-AwakeTimeTracker.secondsSinceLastUserActivity())
            session.lastActiveAt = max(lastActive, session.startedAt)
            session.countedSecondsAtLastActive = Int(awakeTracker.elapsed(now: lastActive))
            activeSession = session
        }
        let carried = Set(activeSession?.carriedOverBundleIds ?? [])
        let used = focusTracker.seconds.filter { !carried.contains($0.key) }
        let candidates = Set(used.keys)
            .union(SwitchPlan.ownedBundleIds(in: profile))
            .subtracting(carried)
        let observed = candidates.sorted().compactMap { AppStateReader.observe(bundleId: $0) }
        let existingURLs = Set(profile.links.compactMap(\.url))
        let hosts = ChromeService.tabURLs()
            .map(\.url)
            .filter { !existingURLs.contains($0) }
            .compactMap { ProfileItem.host(of: $0) }
            .prefix(SessionCapture.maxChromeTabs)
        let snap = SessionSnapshot(
            profileId: profile.id,
            capturedAt: Date(),
            focusSeconds: used,
            observed: observed,
            chromeTabHosts: Array(hosts)
        )
        snapshots = SessionCapture.retain(snapshots, adding: snap)
        persist()
    }

    func lastTimeNote(for bundleId: String?) -> String? {
        guard let bundleId else { return nil }
        let profileId = draft?.id ?? activeSession?.profileId
        guard let profileId else { return nil }
        return SessionCapture.latest(snapshots, for: profileId)?
            .observed.first(where: { $0.bundleId == bundleId && $0.note != nil })?
            .note
    }

    var lastTimeLines: [String] {
        guard let profileId = activeSession?.profileId else { return [] }
        return SessionCapture.latest(snapshots, for: profileId)?
            .observed.compactMap { state -> String? in
                guard let note = state.note else { return nil }
                return "Last time: \(note)"
            } ?? []
    }

    private func sessionEndExtras() -> [InstalledApp] {
        guard let profile = activeProfile else { return [] }
        let snap = SessionCapture.latest(snapshots, for: profile.id)
        let used = Set((snap?.focusSeconds ?? [:]).compactMap { key, value in
            SessionCapture.isUsed(value) ? key : nil
        })
        let extraIds = SessionCapture.extras(
            usedBundleIds: used,
            profile: profile,
            keepOpen: Set(keepOpenBundleIds),
            carriedOver: Set(activeSession?.carriedOverBundleIds ?? [])
        )
        loadInstalledApps()
        let running = LaunchService.foregroundApps()
        return extraIds.compactMap { id in
            installedApps.first(where: { $0.bundleId == id })
                ?? running.first(where: { $0.bundleId == id })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func presentSessionExtras(_ extras: [InstalledApp], profile: Profile) {
        draft = profile
        draftIsNew = false
        proposalFromSessionEnd = true
        proposalItems = extras.map {
            ProposalItem(
                kind: .app(bundleId: $0.bundleId, name: $0.name),
                captureSection: .otherOpen,
                isSelected: false
            )
        }
        proposalUnmatched = []
        screen = .proposal
    }

    // MARK: - AI keys

    private static let consentDefaultsKey = "mevin.screenshotConsent.dontAsk"

    private func statusDefaultsKey(_ provider: AIProvider) -> String {
        "mevin.ai.status.\(provider.rawValue)"
    }

    func keyDraft(for provider: AIProvider) -> String {
        switch provider {
        case .openai: return openaiKeyDraft
        case .deepseek: return deepseekKeyDraft
        }
    }

    func setKeyDraft(_ value: String, for provider: AIProvider) {
        switch provider {
        case .openai: openaiKeyDraft = value
        case .deepseek: deepseekKeyDraft = value
        }
    }

    func hasSavedKey(_ provider: AIProvider) -> Bool {
        KeychainService.hasKey(for: provider)
    }

    var hasOpenAIKey: Bool { hasSavedKey(.openai) }

    func maskedKey(for provider: AIProvider) -> String? {
        KeychainService.masked(for: provider)
    }

    func keyStatus(for provider: AIProvider) -> AIKeyStatus {
        guard hasSavedKey(provider) else { return .notSet }
        let raw = UserDefaults.standard.string(forKey: statusDefaultsKey(provider))
        return AIKeyStatus(rawValue: raw ?? "") ?? .saved
    }

    func canSaveKey(_ provider: AIProvider) -> Bool {
        validatingProvider == nil
            && !keyDraft(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveAPIKey(_ provider: AIProvider) async {
        let key = keyDraft(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validatingProvider = provider
        KeychainService.setKey(key, for: provider)
        let ok = await AIProvider.validate(key, provider: provider)
        UserDefaults.standard.set((ok ? AIKeyStatus.saved : AIKeyStatus.rejected).rawValue, forKey: statusDefaultsKey(provider))
        if ok { setKeyDraft("", for: provider) }
        validatingProvider = nil
    }

    func removeAPIKey(_ provider: AIProvider) {
        KeychainService.deleteKey(for: provider)
        UserDefaults.standard.removeObject(forKey: statusDefaultsKey(provider))
        setKeyDraft("", for: provider)
    }

    // MARK: - Add what's open

    func addWhatsOpen() {
        screenshotError = nil
        loadInstalledApps()
        let existingApps = Set(draft?.items.compactMap(\.bundleId) ?? [])
        let hasChrome = draft?.includesChrome == true
        let existingURLs = Set(draft?.links.compactMap(\.url) ?? [])
        let keep = Set(keepOpenBundleIds)
        var onScreen: [ProposalItem] = []
        var otherOpen: [ProposalItem] = []

        for classified in WindowClassifier.classifyRunningApps() {
            let app = classified.app
            guard !keep.contains(app.bundleId) else { continue }
            if Constants.chromeBundleIDs.contains(app.bundleId) {
                if hasChrome { continue }
            } else if existingApps.contains(app.bundleId) {
                continue
            }
            let section: ProposalItem.CaptureSection =
                classified.bucket == .onScreen ? .onScreen : .otherOpen
            let item = ProposalItem(
                kind: .app(bundleId: app.bundleId, name: app.name),
                captureSection: section,
                isSelected: section == .onScreen
            )
            if section == .onScreen {
                onScreen.append(item)
            } else {
                otherOpen.append(item)
            }
        }

        onScreen.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        otherOpen.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        let tabs = ChromeService.tabURLs()
            .filter { !existingURLs.contains($0.url) }
            .prefix(8)
            .map {
                ProposalItem(kind: .tab(url: $0.url, title: $0.title), captureSection: .tabs, isSelected: false)
            }

        guard !onScreen.isEmpty || !otherOpen.isEmpty || !tabs.isEmpty else { return }
        proposalItems = onScreen + otherOpen + tabs
        proposalUnmatched = []
        screen = .proposal
    }

    var proposalSubtitle: String {
        let onScreen = proposalItems.filter { $0.captureSection == .onScreen }.count
        let other = proposalItems.filter { $0.captureSection == .otherOpen }.count
        let tabs = proposalItems.filter { $0.captureSection == .tabs }.count
        var parts: [String] = []
        if onScreen > 0 { parts.append("\(onScreen) on screen") }
        if other > 0 { parts.append("\(other) other open") }
        if tabs > 0 { parts.append("\(tabs) tabs") }
        if parts.isEmpty { return "Nothing to add" }
        return "Found " + parts.joined(separator: ", ")
    }

    func selectProposalSection(_ section: ProposalItem.CaptureSection, selected: Bool) {
        for index in proposalItems.indices where proposalItems[index].captureSection == section {
            proposalItems[index].isSelected = selected
        }
    }

    func cancelProposal() {
        let fromEnd = proposalFromSessionEnd
        proposalItems = []
        proposalUnmatched = []
        proposalFromSessionEnd = false
        if fromEnd {
            draft = nil
            draftIsNew = false
            screen = .list
        } else {
            screen = .builder
        }
    }

    func confirmProposal() {
        for item in proposalItems where item.isSelected {
            switch item.kind {
            case .app(let bundleId, let name):
                if Constants.chromeBundleIDs.contains(bundleId) {
                    ensureChromeProfileItem()
                } else {
                    addApp(bundleId: bundleId, name: name)
                }
            case .tab(let url, let title):
                addLink(url: url, title: title)
            }
        }
        let fromEnd = proposalFromSessionEnd
        proposalItems = []
        proposalUnmatched = []
        proposalFromSessionEnd = false
        if fromEnd {
            if let draft, let index = profiles.firstIndex(where: { $0.id == draft.id }) {
                profiles[index] = draft
                persist()
            }
            self.draft = nil
            draftIsNew = false
            screen = .list
        } else {
            screen = .builder
        }
    }

    // MARK: - Screenshot

    func handleScreenshot(_ image: NSImage) {
        screenshotError = nil
        switch VisionService.prepare(image) {
        case .failure(let error):
            screenshotError = error.message
        case .success(let jpeg):
            pendingScreenshotJPEG = jpeg
            if UserDefaults.standard.bool(forKey: Self.consentDefaultsKey) {
                Task { await sendPendingScreenshot() }
            } else {
                consentDontAskChecked = false
                showingScreenshotConsent = true
            }
        }
    }

    func confirmScreenshotConsent() {
        showingScreenshotConsent = false
        if consentDontAskChecked {
            UserDefaults.standard.set(true, forKey: Self.consentDefaultsKey)
        }
        Task { await sendPendingScreenshot() }
    }

    func cancelScreenshotConsent() {
        showingScreenshotConsent = false
        pendingScreenshotJPEG = nil
    }

    @discardableResult
    func pasteScreenshotIfPossible() -> Bool {
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        guard hasOpenAIKey else { return false }
        guard let image = VisionService.image(fromPasteboard: .general) else { return false }
        handleScreenshot(image)
        return true
    }

    func handleScreenshotDrop(_ providers: [NSItemProvider]) -> Bool {
        guard hasOpenAIKey else {
            screenshotError = VisionService.Failure.noKey.message
            return false
        }
        return VisionService.loadImage(from: providers) { [weak self] image in
            guard let self, let image else { return }
            self.handleScreenshot(image)
        }
    }

    func browseForScreenshot() {
        guard hasOpenAIKey else {
            screenshotError = VisionService.Failure.noKey.message
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose a screenshot"
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.png, .jpeg, .heic]
        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url, let image = VisionService.image(fromFile: url) else { return }
            self.handleScreenshot(image)
        }
    }

    func sendPendingScreenshot() async {
        guard let jpeg = pendingScreenshotJPEG else { return }
        pendingScreenshotJPEG = nil
        guard let key = KeychainService.key(for: .openai) else {
            screenshotError = VisionService.Failure.noKey.message
            return
        }
        isReadingScreenshot = true
        screenshotError = nil
        let identified = await VisionService.identify(jpeg: jpeg, apiKey: key)
        isReadingScreenshot = false
        switch identified {
        case .failure(let error):
            if error == .rejected {
                UserDefaults.standard.set(AIKeyStatus.rejected.rawValue, forKey: statusDefaultsKey(.openai))
            }
            screenshotError = error.message
        case .success(let names):
            var installed = installedApps
            if installed.isEmpty {
                installed = LaunchService.installedApplications()
                installedApps = installed
            }
            let result = AppMatcher.match(names: names, installed: installed)
            let existing = Set(draft?.items.compactMap(\.bundleId) ?? [])
            let fresh = result.matches.filter { !existing.contains($0.bundleId) }
            if fresh.isEmpty {
                screenshotError = result.matches.isEmpty
                    ? VisionService.Failure.noneFound.message
                    : VisionService.Failure.allAlreadyInProfile.message
                return
            }
            proposalItems = fresh.map {
                ProposalItem(
                    kind: .app(bundleId: $0.bundleId, name: $0.name),
                    captureSection: .otherOpen,
                    isSelected: $0.confidence == .high
                )
            }
            proposalUnmatched = result.unmatched
            screen = .proposal
        }
    }

    // MARK: - Picker data

    /// Scanning /Applications reads a lot of bundles, so it happens off the main
    /// thread and is kept for the life of the session.
    func loadInstalledApps() {
        guard installedApps.isEmpty, !isLoadingApps else { return }
        isLoadingApps = true
        Task {
            let apps = await Task.detached { LaunchService.installedApplications() }.value
            self.installedApps = apps
            self.isLoadingApps = false
        }
    }

    func loadChromeProfiles() {
        chromeLookup = ChromeService.profiles()
    }

    var filteredApps: [InstalledApp] {
        let query = appQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return installedApps }
        return installedApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// The editors actually installed on this Mac. Finder is offered separately,
    /// since it is the default and is not in this list.
    var folderOpenerChoices: [InstalledApp] {
        Constants.editorBundleIDs.compactMap { id in installedApps.first { $0.bundleId == id } }
    }

    // MARK: - Pickers

    func browseForApp() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose an app to open with this profile"
        openPanel.prompt = "Add app"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.application]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url,
                  let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            self.addApp(bundleId: bundleId, name: name)
        }
    }

    func browseForFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose a folder to open with this profile"
        openPanel.prompt = "Add folder"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url else { return }
            self.addFolder(path: url.path)
        }
    }

    func browseForFolderOpener(itemID: UUID) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose an app to open this folder"
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.application]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel?.runPicker(openPanel) { [weak self] url in
            guard let self, let url,
                  let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let app = InstalledApp(bundleId: bundleId, name: name, url: url)
            if bundleId == Constants.terminalBundleID {
                self.folderOpenerMessage = "To run Terminal in a folder, add a tab on the Terminal row."
                return
            }
            self.setFolderOpener(itemID: itemID, app: app)
        }
    }

    func detectChromeProfile() {
        guard !chromeDetecting else { return }
        chromeDetecting = true
        chromeDetectStatus = nil
        chromeEntryError = nil
        Task { @MainActor in
            let result = await ChromeProfileDetectionService.detect(panel: self.panel)
            chromeDetecting = false
            switch result {
            case .success(let detected):
                ChromeDebugLog.log("==== detectChromeProfile: rawPathFragment=\"\(detected.rawPathFragment)\" suggestedName=\(detected.suggestedName ?? "nil")")  // DEBUG-CHROME-LOG
                chromeDirectoryText = detected.rawPathFragment
                // Chrome is still on the detected profile, so its front window's
                // toolbar shows Chrome's own name for it (PRD V7 Change 3).
                if let folder = ChromeService.profileDirectoryName(fromPasted: detected.rawPathFragment),
                   let toolbar = detected.chromeProfileName ?? ChromeWindowService.frontWindowProfileName() {
                    pendingChromeToolbarDirectory = folder
                    pendingChromeToolbarName = toolbar
                }
                if chromeLabelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let suggested = detected.suggestedName {
                    chromeLabelText = suggested
                }
                chromeDetectStatus = "Profile folder detected."
                chromeDidTest = false
            case .failure(let error):
                var message = error.userMessage
                if !CGPreflightScreenCaptureAccess() {
                    message += " Allow Screen Recording for Mevin to detect profiles automatically."
                }
                chromeDetectStatus = message
            }
        }
    }
}
