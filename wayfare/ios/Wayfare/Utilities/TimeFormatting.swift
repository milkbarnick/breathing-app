import Foundation

/// Thread-safe cache, because DateFormatter is expensive to create and timeline rows format a lot.
final class FormatterCache: @unchecked Sendable {
    static let shared = FormatterCache()

    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    /// A formatter for a localized template (e.g. "EEEMMMd") or, when `template` is nil, the short time style.
    func formatter(template: String?, timeZone: TimeZone, locale: Locale) -> DateFormatter {
        let key = "\(template ?? "<shortTime>")|\(timeZone.identifier)|\(locale.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar.gregorian(in: timeZone)
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        } else {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        }
        formatters[key] = formatter
        return formatter
    }
}

/// Pure, time-zone-aware formatting helpers. Nothing here reads the device zone unless it is passed in.
enum TimeFormat {
    /// Minus sign used in offsets ("GMT−4"), per the UX spec.
    static let minusSign = "\u{2212}"

    // MARK: Times and dates

    /// "22:30" or "10:30 PM", following the user's 12/24-hour setting, in `timeZone`.
    static func time(_ date: Date, in timeZone: TimeZone, locale: Locale = .current) -> String {
        FormatterCache.shared.formatter(template: nil, timeZone: timeZone, locale: locale).string(from: date)
    }

    /// Formats `date` in `timeZone` with a localized template such as "EEEMMMd" ("Thu, Oct 1").
    static func date(_ date: Date, template: String, in timeZone: TimeZone, locale: Locale = .current) -> String {
        FormatterCache.shared.formatter(template: template, timeZone: timeZone, locale: locale).string(from: date)
    }

    /// "Thu, Oct 1" for a calendar day.
    static func dayHeader(_ day: CalendarDay, locale: Locale = .current) -> String {
        guard let date = day.startDate(in: .utc) else { return day.string }
        return self.date(date, template: "EEEMMMd", in: .utc, locale: locale)
    }

    /// "Oct 1" for a calendar day.
    static func shortDay(_ day: CalendarDay, locale: Locale = .current) -> String {
        guard let date = day.startDate(in: .utc) else { return day.string }
        return self.date(date, template: "MMMd", in: .utc, locale: locale)
    }

    /// "Oct 1 – 9", "Sep 28 – Oct 3" or, with `includeYear`, "Oct 1 – 9, 2026".
    static func dateRange(_ start: CalendarDay, _ end: CalendarDay, includeYear: Bool = false,
                          locale: Locale = .current) -> String {
        guard let startDate = start.startDate(in: .utc), let endDate = end.startDate(in: .utc) else {
            return "\(start.string) – \(end.string)"
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.timeZone = .utc
        formatter.calendar = Calendar.gregorian(in: .utc)
        formatter.dateTemplate = includeYear ? "yMMMd" : "MMMd"
        return formatter.string(from: startDate, to: max(startDate, endDate))
    }

    /// "Thu, Oct 1 – Fri, Oct 9".
    static func longDateRange(_ start: CalendarDay, _ end: CalendarDay, locale: Locale = .current) -> String {
        if start == end { return dayHeader(start, locale: locale) }
        return "\(dayHeader(start, locale: locale)) – \(dayHeader(end, locale: locale))"
    }

    /// "9 days · 8 nights".
    static func tripLength(_ start: CalendarDay, _ end: CalendarDay) -> String {
        let nights = max(0, start.days(to: end))
        let days = nights + 1
        let dayText = days == 1 ? "1 day" : "\(days) days"
        let nightText = nights == 1 ? "1 night" : "\(nights) nights"
        return "\(dayText) · \(nightText)"
    }

    // MARK: Zones

    /// "GMT+1", "GMT−4", "GMT+5:30", or "GMT" for zero offset.
    static func gmtOffset(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        if seconds == 0 { return "GMT" }
        let sign = seconds < 0 ? minusSign : "+"
        let total = abs(seconds) / 60
        let hours = total / 60
        let minutes = total % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    /// "EDT", or "GMT−4" when the system has no abbreviation for the zone.
    static func zoneAbbreviation(_ timeZone: TimeZone, at date: Date) -> String {
        guard let abbreviation = timeZone.abbreviation(for: date), !abbreviation.isEmpty else {
            return gmtOffset(timeZone, at: date)
        }
        return abbreviation.replacingOccurrences(of: "-", with: minusSign)
    }

    /// "New York" from "America/New_York".
    static func city(forZoneIdentifier identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// "Lisbon (GMT+1)".
    static func zoneLabel(_ identifier: String, at date: Date = Date()) -> String {
        let zone = TimeZone.resolve(identifier, fallback: .utc)
        return "\(city(forZoneIdentifier: identifier)) (\(gmtOffset(zone, at: date)))"
    }

    /// The zone badge for a time shown in a timeline section, or nil when no badge is needed.
    /// A badge appears only when the item zone's UTC offset differs from the trip zone's at that instant
    /// (identifiers are not compared). When the item's local date differs from the section's date,
    /// the badge also carries the local date: "Oct 1 · EDT".
    static func zoneBadge(for instant: Date, itemZone: TimeZone, tripZone: TimeZone,
                          sectionDay: CalendarDay?, locale: Locale = .current) -> String? {
        guard itemZone.secondsFromGMT(for: instant) != tripZone.secondsFromGMT(for: instant) else {
            return nil
        }
        let abbreviation = zoneAbbreviation(itemZone, at: instant)
        let localDay = CalendarDay(date: instant, in: itemZone)
        if let sectionDay, localDay != sectionDay {
            return "\(shortDay(localDay, locale: locale)) · \(abbreviation)"
        }
        return abbreviation
    }

    // MARK: Day offsets and durations

    /// Difference in local calendar dates between the end (in its zone) and the start (in its zone).
    /// +1 for an overnight flight, −1 for an eastbound date-line crossing that "arrives yesterday".
    static func dayOffset(start: Date, startZone: TimeZone, end: Date, endZone: TimeZone) -> Int {
        let startDay = CalendarDay(date: start, in: startZone)
        let endDay = CalendarDay(date: end, in: endZone)
        return startDay.days(to: endDay)
    }

    /// "+1", "+2", "−1", or nil for 0.
    static func dayOffsetSuffix(_ offset: Int) -> String? {
        if offset == 0 { return nil }
        return offset > 0 ? "+\(offset)" : "\(minusSign)\(abs(offset))"
    }

    /// "7 h 15 min", "45 min", "2 h". Always computed from instants.
    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
        return durationText(minutes: minutes)
    }

    static func durationText(minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) d") }
        if hours > 0 { parts.append("\(hours) h") }
        if mins > 0 || parts.isEmpty { parts.append("\(mins) min") }
        return parts.joined(separator: " ")
    }

    /// "in 2 h 15 min", "in 5 min", "now".
    static func relative(from now: Date, to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 60 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        return "in \(durationText(minutes: minutes))"
    }

    /// Countdown chip on trip rows: "Today", "Tomorrow", "in 12 days", "in 3 wks", "in 4 mo".
    static func countdown(daysUntil days: Int) -> String {
        switch days {
        case ..<1: return "Today"
        case 1: return "Tomorrow"
        case 2...20: return "in \(days) days"
        case 21...60: return "in \(Int((Double(days) / 7).rounded())) wks"
        default: return "in \(Int((Double(days) / 30).rounded())) mo"
        }
    }

    // MARK: Reminders

    /// Presets from the UX spec, in minutes. nil = no reminder.
    static let reminderPresets: [Int?] = [nil, 0, 5, 15, 30, 60, 120, 180, 1440, 2880]

    /// "At time of event", "15 min before", "3 hours before", "1 day before", "None".
    static func reminderLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "None" }
        return minutes == 0 ? "At time of event" : "\(reminderAmount(minutes)) before"
    }

    /// "15 min", "1 hour", "3 hours", "1 day", "2 days".
    static func reminderAmount(_ minutes: Int) -> String {
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? "1 day" : "\(days) days"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) min"
    }

    /// "2 min ago", "just now", "Never".
    static func lastSynced(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        return "\(hours / 24) d ago"
    }
}
