import AppKit
import Foundation
import UserNotifications

extension AppModel {
    // MARK: - Role usage

    func usageSummary(for profileId: UUID) -> RoleUsageStats.Summary {
        RoleUsageStats.summary(for: profileId, records: roleUses)
    }

    var mostUsedProfileID: UUID? {
        RoleUsageStats.mostUsedProfileId(in: roleUses, profiles: profiles)
    }

    func finalizeCurrentRoleUse(trimToLastActivity: Bool, endAt: Date? = nil) {
        guard let session = activeSession, let started = roleUseStartedAt else { return }
        let endedAt: Date
        let counted: TimeInterval
        if let endAt {
            endedAt = endAt
            counted = awakeTracker.elapsed(now: endAt)
            _ = awakeTracker.stop()
        } else if trimToLastActivity {
            let idle = AwakeTimeTracker.secondsSinceLastUserActivity()
            endedAt = Date().addingTimeInterval(-idle)
            counted = awakeTracker.elapsed(now: endedAt)
            _ = awakeTracker.stop()
        } else {
            endedAt = Date()
            counted = awakeTracker.stop()
        }
        let seconds = max(0, Int(counted))
        if seconds >= RoleUsageStats.minimumCountedSeconds {
            roleUses.append(
                RoleUseRecord(
                    profileId: session.profileId,
                    startedAt: started,
                    endedAt: endedAt,
                    countedSeconds: seconds
                )
            )
            persist()
        }
        roleUseStartedAt = nil
    }

    // MARK: - Session lifecycle (timer + check-ins)

    func beginSessionLifecycle(for profile: Profile) {
        cancelSessionLifecycleTasks()
        roleUseStartedAt = activeSession?.startedAt ?? Date()
        awakeTracker.start(from: roleUseStartedAt ?? Date())
        checkInAwakeBaseline = 0
        checkInUnansweredSince = nil
        timerFiredForCurrentSetting = false
        timerSetAtAwake = 0
        inAppTimerPrompt = false
        inAppCheckInPrompt = false
        if activeTimerMinutes == nil, let defaultMinutes = profile.defaultTimerMinutes, defaultMinutes > 0 {
            activeTimerMinutes = defaultMinutes
        }
        rescheduleTimerNotificationIfNeeded(for: profile)
        sessionLifecycleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                self.sessionLifecycleTick()
            }
        }
        panel?.refreshStatusIcon()
    }

    func cancelSessionLifecycle() {
        cancelSessionLifecycleTasks()
        activeTimerMinutes = nil
        timerRepeatPrefillMinutes = nil
        MevinNotificationService.cancelTimer(profileId: activeSession?.profileId ?? UUID())
        MevinNotificationService.cancelCheckIn(profileId: activeSession?.profileId ?? UUID())
        panel?.refreshStatusIcon()
    }

    private func cancelSessionLifecycleTasks() {
        sessionLifecycleTask?.cancel()
        sessionLifecycleTask = nil
        checkInAutoEndTask?.cancel()
        checkInAutoEndTask = nil
    }

    func promptCustomTimer(forProfileID profileID: UUID) {
        let alert = NSAlert()
        alert.messageText = "Session timer"
        alert.informativeText = "How many minutes until Mevin reminds you?"
        let existing = isRunning(profileID)
            ? activeTimerMinutes
            : profile(id: profileID)?.defaultTimerMinutes
        let minutes = existing ?? timerRepeatPrefillMinutes ?? 25
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 96, height: 24))
        field.stringValue = "\(minutes)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard value > 0 else { return }
        if isRunning(profileID) {
            setActiveTimer(minutes: value)
        } else {
            setProfileDefaultTimer(profileID: profileID, minutes: value)
        }
        timerRepeatPrefillMinutes = value
    }

    func setProfileDefaultTimer(profileID: UUID, minutes: Int?) {
        guard var profile = profile(id: profileID),
              let index = profiles.firstIndex(where: { $0.id == profileID })
        else { return }
        profile.defaultTimerMinutes = minutes
        profiles[index] = profile
        persist()
    }

    func setActiveTimer(minutes: Int?) {
        guard activeSession != nil else { return }
        activeTimerMinutes = minutes
        timerSetAtAwake = awakeTracker.elapsed()
        timerFiredForCurrentSetting = false
        inAppTimerPrompt = false
        if let profile = activeProfile {
            if let minutes, minutes > 0 {
                rescheduleTimerNotificationIfNeeded(for: profile)
            } else {
                MevinNotificationService.cancelTimer(profileId: profile.id)
            }
        }
        if activeTimerMinutes == nil {
            checkInAwakeBaseline = awakeTracker.elapsed()
        }
        panel?.refreshStatusIcon()
    }

    func setDraftDefaultTimer(minutes: Int?) {
        guard var current = draft else { return }
        current.defaultTimerMinutes = minutes
        draft = current
    }

    func setCheckInIntervalHours(_ hours: Int) {
        checkInIntervalHours = hours
        persist()
    }

    /// Seconds left on the running timer, or nil with no timer.
    var timerRemainingSeconds: TimeInterval? {
        guard let minutes = activeTimerMinutes, minutes > 0, activeSession != nil else { return nil }
        return SessionClock.remainingSeconds(
            minutes: minutes,
            setAtAwake: timerSetAtAwake,
            awakeNow: awakeTracker.elapsed()
        )
    }

    var menuBarTimerLabel: String? {
        timerRemainingSeconds.map(SessionClock.menuBarLabel(remaining:))
    }

    private func sessionLifecycleTick() {
        guard let profile = activeProfile else { return }
        panel?.refreshStatusIcon()
        evaluateTimer(profile: profile)
        evaluateCheckIn(profile: profile)
    }

    private func evaluateTimer(profile: Profile) {
        guard let minutes = activeTimerMinutes, minutes > 0, !timerFiredForCurrentSetting,
              let remaining = timerRemainingSeconds
        else { return }
        guard remaining <= 0 else {
            rescheduleTimerNotificationIfNeeded(for: profile)
            return
        }
        timerFiredForCurrentSetting = true
        Task {
            let ok = await MevinNotificationService.requestAuthorizationIfNeeded()
            await MainActor.run {
                self.notificationsDenied = !ok
                if ok {
                    MevinNotificationService.scheduleTimerEnd(
                        roleName: profile.name,
                        profileId: profile.id,
                        fireAt: Date().addingTimeInterval(1)
                    )
                } else {
                    self.inAppTimerPrompt = true
                    self.timerRepeatPrefillMinutes = minutes
                    self.panel?.show()
                }
            }
        }
    }

    private func rescheduleTimerNotificationIfNeeded(for profile: Profile) {
        guard !timerFiredForCurrentSetting, let left = timerRemainingSeconds else { return }
        let remaining = max(1, left)
        MevinNotificationService.cancelTimer(profileId: profile.id)
        Task {
            let ok = await MevinNotificationService.requestAuthorizationIfNeeded()
            await MainActor.run {
                self.notificationsDenied = !ok
                if ok {
                    MevinNotificationService.scheduleTimerEnd(
                        roleName: profile.name,
                        profileId: profile.id,
                        fireAt: Date().addingTimeInterval(remaining)
                    )
                }
            }
        }
    }

    private func evaluateCheckIn(profile: Profile) {
        guard checkInIntervalHours > 0 else { return }
        guard activeTimerMinutes == nil else { return }
        let interval = TimeInterval(checkInIntervalHours * 3600)
        let sinceBaseline = awakeTracker.elapsed() - checkInAwakeBaseline
        guard sinceBaseline >= interval else { return }
        guard checkInUnansweredSince == nil else { return }

        checkInUnansweredSince = Date()
        Task {
            let ok = await MevinNotificationService.requestAuthorizationIfNeeded()
            await MainActor.run {
                self.notificationsDenied = !ok
                if ok {
                    MevinNotificationService.scheduleCheckIn(
                        roleName: profile.name,
                        profileId: profile.id,
                        fireAt: Date().addingTimeInterval(1)
                    )
                } else {
                    self.inAppCheckInPrompt = true
                    self.panel?.show()
                }
                self.scheduleCheckInAutoEnd(for: profile)
            }
        }
        checkInAwakeBaseline = awakeTracker.elapsed()
    }

    private func scheduleCheckInAutoEnd(for profile: Profile) {
        checkInAutoEndTask?.cancel()
        checkInAutoEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30 * 60))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.activeSession?.profileId == profile.id,
                      self.checkInUnansweredSince != nil
                else { return }
                self.performAutoEndSession(profile: profile)
            }
        }
    }

    func performAutoEndSession(profile: Profile) {
        finalizeCurrentRoleUse(trimToLastActivity: true)
        let lastActivity = Date().addingTimeInterval(-AwakeTimeTracker.secondsSinceLastUserActivity())
        autoEndBanner = AutoEndBanner(
            profileId: profile.id,
            profileName: profile.name,
            lastActivityAt: lastActivity
        )
        stopCapture()
        cancelSessionLifecycle()
        activeSession = nil
        persist()
        panel?.refreshStatusIcon()
        checkInUnansweredSince = nil
    }

    func respondToCheckInContinue() {
        inAppCheckInPrompt = false
        checkInUnansweredSince = nil
        checkInAutoEndTask?.cancel()
        checkInAutoEndTask = nil
        checkInAwakeBaseline = awakeTracker.elapsed()
        MevinNotificationService.cancelCheckIn(profileId: activeProfile?.id ?? UUID())
    }

    /// Opens the usual end panel. The session keeps running until the end is
    /// confirmed; its recorded time stops at this click (PRD V7 Change 6).
    func respondToCheckInEnd() {
        inAppCheckInPrompt = false
        checkInUnansweredSince = nil
        checkInAutoEndTask?.cancel()
        checkInAutoEndTask = nil
        endRequestedAt = Date()
        beginEndFlow()
        panel?.show()
    }

    func continueAfterTimerWithoutExtension() {
        inAppTimerPrompt = false
        activeTimerMinutes = nil
        timerRepeatPrefillMinutes = nil
        if let id = activeProfile?.id {
            MevinNotificationService.cancelTimer(profileId: id)
        }
        checkInAwakeBaseline = awakeTracker.elapsed()
        panel?.refreshStatusIcon()
    }

    func openPanelForNewTimerAfterExpiry() {
        inAppTimerPrompt = false
        let minutes = timerRepeatPrefillMinutes ?? activeTimerMinutes
        timerRepeatPrefillMinutes = minutes
        timerFiredForCurrentSetting = false
        if let minutes {
            setActiveTimer(minutes: minutes)
        }
        panel?.show()
    }

    func dismissAutoEndBanner() {
        autoEndBanner = nil
    }

    func startFromAutoEndBanner() {
        guard let banner = autoEndBanner else { return }
        autoEndBanner = nil
        startOrEndSession(profileID: banner.profileId)
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let action = response.actionIdentifier
        let profileIdString = response.notification.request.content.userInfo["profileId"] as? String
        let profileId = profileIdString.flatMap(UUID.init(uuidString:))

        switch action {
        case "newTimer", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == MevinNotificationService.Kind.sessionTimer.rawValue {
                timerRepeatPrefillMinutes = activeTimerMinutes
                openPanelForNewTimerAfterExpiry()
            }
        case "continueNoTimer":
            continueAfterTimerWithoutExtension()
        case "checkInContinue":
            respondToCheckInContinue()
        case "checkInEnd":
            if profileId != nil { respondToCheckInEnd() }
        default:
            break
        }
    }

    func recordAbandonedSessionOnQuit() {
        guard activeSession != nil else { return }
        finalizeCurrentRoleUse(trimToLastActivity: true)
        activeSession = nil
        persist()
    }
}
