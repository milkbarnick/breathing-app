import Foundation
import UserNotifications

/// Schedules local reminders for items with `reminderMinutes` (UNCalendarNotificationTrigger).
/// Rescheduled after every local save, every sync, and on foreground.
@MainActor
final class NotificationScheduler {
    static let reminderCategory = "ITEM_REMINDER"
    static let reminderWithCodeCategory = "ITEM_REMINDER_CODE"
    static let directionsAction = "DIRECTIONS"
    static let copyCodeAction = "COPY_CODE"

    private let center: UNUserNotificationCenter?
    /// Returns every live (not pending-delete) item. Set by AppServices.
    var itemsProvider: () -> [ItemSnapshot] = { [] }

    private var rescheduleTask: Task<Void, Never>?
    private var rescheduleAgain = false

    /// Pass `enabled: false` in previews and tests.
    init(enabled: Bool = true) {
        center = enabled ? UNUserNotificationCenter.current() : nil
    }

    func registerCategories() {
        guard let center else { return }
        let directions = UNNotificationAction(identifier: Self.directionsAction, title: "Directions",
                                              options: [.foreground])
        let copyCode = UNNotificationAction(identifier: Self.copyCodeAction, title: "Copy Code",
                                            options: [.foreground])
        let plain = UNNotificationCategory(identifier: Self.reminderCategory, actions: [directions],
                                           intentIdentifiers: [], options: [])
        let withCode = UNNotificationCategory(identifier: Self.reminderWithCodeCategory,
                                              actions: [directions, copyCode], intentIdentifiers: [], options: [])
        center.setNotificationCategories([plain, withCode])
    }

    /// Coalesces overlapping requests into one pass.
    func reschedule() {
        if rescheduleTask != nil {
            rescheduleAgain = true
            return
        }
        rescheduleTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rescheduleAgain = false
                await self.performReschedule()
            } while self.rescheduleAgain
            self.rescheduleTask = nil
        }
    }

    private func performReschedule() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let plan = ReminderPlanner.plan(items: itemsProvider(), now: Date(), deviceZone: .current)
        let desired = Set(plan.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter {
            $0.hasPrefix(ReminderPlanner.identifierPrefix) && !desired.contains($0)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for reminder in plan {
            try? await center.add(makeRequest(reminder))
        }
    }

    /// Removes every item reminder (sign-out, account deletion).
    func cancelAll() {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func makeRequest(_ reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.tripId
        content.categoryIdentifier = reminder.hasConfirmationCode ? Self.reminderWithCodeCategory : Self.reminderCategory
        content.userInfo = ["type": "reminder", "tripId": reminder.tripId, "itemId": reminder.itemId]

        // Components carry an explicit UTC zone, so the reminder fires at the right instant even
        // if the device changes time zone before it fires.
        let calendar = Calendar.gregorian(in: .utc)
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                 from: reminder.fireDate)
        components.calendar = calendar
        components.timeZone = .utc
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}
