import Foundation

extension TimeZone {
    /// UTC. Used for pure calendar-date arithmetic, which must never see a DST change.
    static let utc: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current

    /// Resolves an IANA identifier, falling back when it is empty or unknown.
    static func resolve(_ identifier: String?, fallback: TimeZone = .current) -> TimeZone {
        guard let identifier, !identifier.isEmpty, let zone = TimeZone(identifier: identifier) else {
            return fallback
        }
        return zone
    }
}

extension Calendar {
    /// A Gregorian calendar pinned to one time zone.
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// A calendar date with no time and no zone, as in the contract's `"YYYY-MM-DD"`.
struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `"YYYY-MM-DD"`. Rejects anything else, including impossible dates like 2026-02-30.
    init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        let candidate = CalendarDay(year: year, month: month, day: day)
        guard let date = candidate.startDate(in: .utc),
              CalendarDay(date: date, in: .utc) == candidate else {
            return nil
        }
        self = candidate
    }

    /// The local calendar date of `date` as seen in `timeZone`.
    init(date: Date, in timeZone: TimeZone) {
        let components = Calendar.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    static func today(in timeZone: TimeZone, now: Date = Date()) -> CalendarDay {
        CalendarDay(date: now, in: timeZone)
    }

    /// `"YYYY-MM-DD"`.
    var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var description: String { string }

    /// Local midnight of this day in `timeZone`.
    func startDate(in timeZone: TimeZone) -> Date? {
        Calendar.gregorian(in: timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    /// A wall-clock time on this day in `timeZone`. DST gaps are resolved by the system (moved forward).
    func date(hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        Calendar.gregorian(in: timeZone).date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )
    }

    func adding(days: Int) -> CalendarDay {
        let calendar = Calendar.gregorian(in: .utc)
        guard let start = startDate(in: .utc),
              let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return self
        }
        return CalendarDay(date: moved, in: .utc)
    }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    func days(to other: CalendarDay) -> Int {
        guard let from = startDate(in: .utc), let to = other.startDate(in: .utc) else { return 0 }
        return Calendar.gregorian(in: .utc).dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
