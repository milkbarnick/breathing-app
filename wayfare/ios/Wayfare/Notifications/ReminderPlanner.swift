import Foundation

/// One local reminder to schedule.
struct PlannedReminder: Equatable, Sendable {
    let identifier: String
    let itemId: String
    let tripId: String
    let fireDate: Date
    let title: String
    let body: String
    let hasConfirmationCode: Bool
}

/// Pure planning for local item reminders (UX spec 4.1). No UserNotifications here, so it is unit-testable.
enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app. We use 60 to leave headroom.
    static let maxPending = 60
    /// Only reminders firing within the next 60 days are scheduled; the rest are topped up later.
    static let horizon: TimeInterval = 60 * 24 * 60 * 60

    static let identifierPrefix = "item-"

    /// Stable identifier `item-<id>`, so rescheduling replaces rather than duplicates.
    static func identifier(for itemId: String) -> String {
        identifierPrefix + itemId.lowercased()
    }

    /// `startAt − reminderMinutes` (lodging: relative to check-in, which is `startAt`). nil = no reminder.
    static func fireDate(startAt: Date, reminderMinutes: Int?) -> Date? {
        guard let reminderMinutes, reminderMinutes >= 0 else { return nil }
        return startAt.addingTimeInterval(-TimeInterval(reminderMinutes) * 60)
    }

    /// Every future reminder within the horizon, capped to the `limit` soonest.
    static func plan(items: [ItemSnapshot], now: Date, deviceZone: TimeZone,
                     locale: Locale = .current, limit: Int = maxPending) -> [PlannedReminder] {
        let candidates: [PlannedReminder] = items.compactMap { item in
            guard let fire = fireDate(startAt: item.startAt, reminderMinutes: item.reminderMinutes) else {
                return nil
            }
            return PlannedReminder(
                identifier: identifier(for: item.id),
                itemId: item.id,
                tripId: item.tripId,
                fireDate: fire,
                title: item.title.isEmpty ? item.kind.displayName : item.title,
                body: body(for: item, deviceZone: deviceZone, locale: locale),
                hasConfirmationCode: !item.confirmationCode.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
        return selectSoonest(candidates, now: now, limit: limit)
    }

    /// Keeps reminders that fire after `now` and within the horizon, sorted by fire date, capped at `limit`.
    static func selectSoonest(_ reminders: [PlannedReminder], now: Date, limit: Int = maxPending) -> [PlannedReminder] {
        let latest = now.addingTimeInterval(horizon)
        return reminders
            .filter { $0.fireDate > now && $0.fireDate <= latest }
            .sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
            .prefix(max(0, limit))
            .map { $0 }
    }

    // MARK: Copy

    /// Body text by kind. Times are in the item's own zone; the zone abbreviation is appended when
    /// it differs from the device's current zone. Empty segments are omitted cleanly.
    static func body(for item: ItemSnapshot, deviceZone: TimeZone, locale: Locale = .current) -> String {
        let time = timeText(item.startAt, zone: item.startZone, deviceZone: deviceZone, locale: locale)
        let code = nonEmpty(item.confirmationCode)
        let location = nonEmpty(item.locationName)
        var text: String

        switch item.kind {
        case .flight:
            text = "Departs \(time)"
            if let from = item.detail("fromCode") ?? location {
                text += " from \(from)"
            }
            if let terminal = item.detail("terminal") { text += " · Terminal \(terminal)" }
            if let seat = item.detail("seat") { text += " · Seat \(seat)" }
            text += "."
            if let code { text += " Confirmation \(code)." }
        case .lodging:
            text = "Check-in \(time)"
            if let location { text += " at \(location)" }
            text += "."
            if let code { text += " Confirmation \(code)." }
        case .transport:
            text = "Departs \(time)"
            if let from = item.detail("fromName") ?? location {
                text += " from \(from)"
            }
            if let seat = item.detail("seat") { text += " · Seat \(seat)" }
            text += "."
        case .food:
            text = "Table"
            if let party = item.detail("partySize") { text += " for \(party)" }
            text += " at \(time)"
            if let location { text += " · \(location)" }
            text += "."
        case .activity:
            text = "Starts at \(time)"
            if let location { text += " · \(location)" }
            text += "."
        case .note:
            text = item.firstNoteLine ?? time
        }

        if item.reminderMinutes == 0 {
            text = "Now: " + text
        }
        return text
    }

    static func timeText(_ date: Date, zone: TimeZone, deviceZone: TimeZone, locale: Locale) -> String {
        let time = TimeFormat.time(date, in: zone, locale: locale)
        if zone.secondsFromGMT(for: date) != deviceZone.secondsFromGMT(for: date) {
            return "\(time) \(TimeFormat.zoneAbbreviation(zone, at: date))"
        }
        return time
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
