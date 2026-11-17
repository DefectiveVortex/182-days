import Foundation
@preconcurrency import UserNotifications
import DaysCore

/// Keeps the pending notifications equal to `NotificationPlanner`'s plan. Owner: Days 1.
/// Runs in the app and in the widget extension (interactive widgets log there), so both replan.
@MainActor
public enum NotificationScheduler {
    static let idPrefix = "days."

    public static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Actions log without opening the app.
    public static func registerCategories() {
        func action(_ a: NotificationAction, _ title: String) -> UNNotificationAction {
            UNNotificationAction(identifier: a.rawValue, title: title, options: [])
        }
        let log = [action(.pushUps10, "+10 push-ups"), action(.sitUps10, "+10 sit-ups")]
        let line = UNTextInputNotificationAction(
            identifier: NotificationAction.closeLine.rawValue, title: "Write the line", options: [],
            textInputButtonTitle: "Save", textInputPlaceholder: "Better than yesterday:")
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: NotificationCategory.log.rawValue, actions: log, intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.posture.rawValue,
                                   actions: [action(.upright, "Upright"), action(.slouching, "Slouching")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.close.rawValue, actions: [line] + log,
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.block.rawValue,
                                   actions: [action(.blockOnIt, "On it"), action(.blockSkip, "Skip")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.photo.rawValue, actions: [], intentIdentifiers: []),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Replaces every pending notification of ours with the current plan.
    public static func replan(_ store: LogStore) async {
        guard !store.isEphemeral else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let plan = NotificationPlanner.plan(now: store.now(), clock: store.clock, settings: store.settings,
                                            today: store.today(), schedule: store.schedule,
                                            photoDays: store.posturePhotos().map(\.day))
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        // Delivered must-day reminders are stale once the day is kept.
        if store.today().kept {
            let delivered = await center.deliveredNotifications()
                .map(\.request.identifier).filter { $0.hasPrefix(idPrefix + "must-") }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
        let cal = store.clock.calendar
        for n in plan {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            content.categoryIdentifier = n.category.rawValue
            content.threadIdentifier = n.kind.rawValue
            content.interruptionLevel = n.kind == .must ? .timeSensitive : .active
            if let block = n.blockID { content.userInfo = ["block": block.uuidString] }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: n.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: idPrefix + n.id, content: content, trigger: trigger))
        }
    }

    /// What a tapped action does. Called by the app's notification delegate.
    public static func handle(action: String, text: String?, store: LogStore) {
        switch NotificationAction(rawValue: action) {
        case .pushUps10: store.log(.pushUps, 10)
        case .sitUps10: store.log(.sitUps, 10)
        case .upright: store.answerPosture(upright: true)
        case .slouching: store.answerPosture(upright: false)
        case .closeLine:
            if let line = text?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                store.setJournalLine(line)
            }
        case .blockOnIt, .blockSkip, nil: break // M2: block answers
        }
    }
}
