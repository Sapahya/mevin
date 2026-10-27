import Foundation
import UserNotifications

enum MevinNotificationService {
    enum Kind: String {
        case sessionTimer = "mevin.sessionTimer"
        case checkIn = "mevin.checkIn"
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    static func scheduleTimerEnd(roleName: String, profileId: UUID, fireAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = "\(roleName): time's up"
        content.body = "Do you want to continue?"
        content.categoryIdentifier = Kind.sessionTimer.rawValue
        content.userInfo = ["profileId": profileId.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireAt.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "timer-\(profileId.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleCheckIn(roleName: String, profileId: UUID, fireAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Still using \"\(roleName)\"?"
        content.body = "Tap an action to respond."
        content.categoryIdentifier = Kind.checkIn.rawValue
        content.userInfo = ["profileId": profileId.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireAt.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "checkin-\(profileId.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelTimer(profileId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["timer-\(profileId.uuidString)"])
    }

    static func cancelCheckIn(profileId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["checkin-\(profileId.uuidString)"])
    }

    static func registerCategories() {
        let timer = UNNotificationCategory(
            identifier: Kind.sessionTimer.rawValue,
            actions: [
                UNNotificationAction(identifier: "newTimer", title: "New timer", options: [.foreground]),
                UNNotificationAction(identifier: "continueNoTimer", title: "Continue without timer", options: [])
            ],
            intentIdentifiers: []
        )
        let checkIn = UNNotificationCategory(
            identifier: Kind.checkIn.rawValue,
            actions: [
                UNNotificationAction(identifier: "checkInContinue", title: "Yes, continue", options: []),
                UNNotificationAction(identifier: "checkInEnd", title: "End session", options: [.foreground])
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([timer, checkIn])
    }
}
