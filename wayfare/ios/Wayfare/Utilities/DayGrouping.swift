import Foundation

// MARK: - Trip phase

/// Where "today" (in the trip's zone) falls relative to a trip's dates.
enum TripPhase: Equatable, Sendable {
    case upcoming(daysUntil: Int)
    case inProgress(dayNumber: Int, totalDays: Int)
    case past

    static func of(start: CalendarDay, end: CalendarDay, timeZone: TimeZone, now: Date) -> TripPhase {
        let today = CalendarDay.today(in: timeZone, now: now)
        let lastDay = max(start, end)
        if today < start {
            return .upcoming(daysUntil: today.days(to: start))
        }
        if today > lastDay {
            return .past
        }
        return .inProgress(dayNumber: start.days(to: today) + 1, totalDays: start.days(to: lastDay) + 1)
    }

    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }

    /// Now/Next highlighting runs while the trip is in progress or on the day before it starts.
    var highlightsNowNext: Bool {
        switch self {
        case .inProgress: return true
        case .upcoming(let days): return days <= 1
        case .past: return false
        }
    }
}

// MARK: - Timeline model

struct TimelineRow: Identifiable, Hashable, Sendable {
    enum Role: Hashable, Sendable {
        /// Any non-lodging item.
        case single
        /// Lodging check-in. `nights` is 0 when there is no (later) check-out.
        case checkIn(nights: Int)
        /// The slim "Staying at X · Night n of N" band on an intermediate day.
        case staying(night: Int, of: Int)
        case checkOut
    }

    let item: ItemSnapshot
    let role: Role
    /// The section (trip-zone day) this row belongs to.
    let day: CalendarDay

    var id: String {
        let roleKey: String
        switch role {
        case .single: roleKey = "item"
        case .checkIn: roleKey = "in"
        case .staying(let night, _): roleKey = "stay\(night)"
        case .checkOut: roleKey = "out"
        }
        return "\(item.id)|\(roleKey)|\(day.string)"
    }

    var isBand: Bool {
        if case .staying = role { return true }
        return false
    }

    var isCheckOut: Bool { role == .checkOut }

    /// The instant shown in the time column: check-out rows show the end.
    var displayInstant: Date {
        isCheckOut ? (item.endAt ?? item.startAt) : item.startAt
    }

    var displayZone: TimeZone {
        isCheckOut ? item.endZone : item.startZone
    }
}

struct TimelineSection: Identifiable, Hashable, Sendable {
    enum Placement: Hashable, Sendable {
        case beforeTrip
        case trip(dayNumber: Int)
        case afterTrip
    }

    let day: CalendarDay
    let placement: Placement
    var rows: [TimelineRow]

    var id: String { day.string }
}

// MARK: - Grouping

/// Day grouping rules from UX spec 3.3.1 and 5.1. Pure functions.
enum DayGrouping {
    /// Safety cap so a corrupt date range can't build millions of sections.
    static let maxTripDays = 400

    /// The trip-zone day an item belongs to. All-day items keep their own local date (they never drift).
    static func groupingDay(for item: ItemSnapshot, tripZone: TimeZone) -> CalendarDay {
        if item.allDay {
            return CalendarDay(date: item.startAt, in: item.startZone)
        }
        return CalendarDay(date: item.startAt, in: tripZone)
    }

    /// Rows for one item. Lodging with a later check-out day expands into check-in, staying bands and check-out.
    static func rows(for item: ItemSnapshot, tripZone: TimeZone) -> [TimelineRow] {
        let startDay = groupingDay(for: item, tripZone: tripZone)
        guard item.kind == .lodging else {
            return [TimelineRow(item: item, role: .single, day: startDay)]
        }
        guard let endAt = item.endAt else {
            return [TimelineRow(item: item, role: .checkIn(nights: 0), day: startDay)]
        }
        let endDay = item.allDay ? CalendarDay(date: endAt, in: item.endZone) : CalendarDay(date: endAt, in: tripZone)
        let nights = startDay.days(to: endDay)
        guard nights > 0 else {
            return [TimelineRow(item: item, role: .checkIn(nights: 0), day: startDay)]
        }
        var rows = [TimelineRow(item: item, role: .checkIn(nights: nights), day: startDay)]
        if nights >= 2 {
            for offset in 1..<nights {
                rows.append(TimelineRow(item: item, role: .staying(night: offset + 1, of: nights),
                                        day: startDay.adding(days: offset)))
            }
        }
        rows.append(TimelineRow(item: item, role: .checkOut, day: endDay))
        return rows
    }

    /// Sections for every trip day (empty days included), plus Before/After sections only for days that
    /// hold a real row. Staying bands never create a section on their own.
    static func sections(items: [ItemSnapshot], tripStart: CalendarDay, tripEnd: CalendarDay,
                         tripZone: TimeZone) -> [TimelineSection] {
        let start = tripStart
        let end = min(max(tripStart, tripEnd), tripStart.adding(days: maxTripDays))

        var rowsByDay: [CalendarDay: [TimelineRow]] = [:]
        var extraDays = Set<CalendarDay>()
        for item in items {
            for row in rows(for: item, tripZone: tripZone) {
                rowsByDay[row.day, default: []].append(row)
                if !row.isBand && (row.day < start || row.day > end) {
                    extraDays.insert(row.day)
                }
            }
        }

        var sections: [TimelineSection] = []
        for day in extraDays.filter({ $0 < start }).sorted() {
            sections.append(TimelineSection(day: day, placement: .beforeTrip, rows: sortRows(rowsByDay[day] ?? [])))
        }
        var day = start
        var dayNumber = 1
        while day <= end {
            sections.append(TimelineSection(day: day, placement: .trip(dayNumber: dayNumber),
                                            rows: sortRows(rowsByDay[day] ?? [])))
            day = day.adding(days: 1)
            dayNumber += 1
        }
        for day in extraDays.filter({ $0 > end }).sorted() {
            sections.append(TimelineSection(day: day, placement: .afterTrip, rows: sortRows(rowsByDay[day] ?? [])))
        }
        return sections
    }

    /// Bands first, then all-day items by sortIndex, then timed rows by time, sortIndex, title.
    static func sortRows(_ rows: [TimelineRow]) -> [TimelineRow] {
        let bands = rows.filter(\.isBand).sorted { $0.item.title < $1.item.title }
        let allDay = rows.filter { !$0.isBand && $0.item.allDay }
            .sorted { ($0.item.sortIndex, $0.item.title) < ($1.item.sortIndex, $1.item.title) }
        let timed = rows.filter { !$0.isBand && !$0.item.allDay }
            .sorted {
                ($0.displayInstant, $0.item.sortIndex, $0.item.title) < ($1.displayInstant, $1.item.sortIndex, $1.item.title)
            }
        return bands + allDay + timed
    }

    /// The section to show as "today" and to scroll to, if any.
    static func todaySection(in sections: [TimelineSection], tripZone: TimeZone, now: Date) -> TimelineSection? {
        let today = CalendarDay.today(in: tripZone, now: now)
        return sections.first { $0.day == today }
    }
}

// MARK: - Now / Next

enum NowNext {
    /// Now: timed, non-lodging items with startAt ≤ now < endAt. Next: the first timed, non-lodging item
    /// that starts after now. Only one item is ever Next.
    static func compute(items: [ItemSnapshot], now: Date) -> (now: Set<String>, next: String?) {
        let timed = items.filter { !$0.allDay && $0.kind != .lodging }
        var nowIds = Set<String>()
        for item in timed {
            if let end = item.endAt, item.startAt <= now, now < end {
                nowIds.insert(item.id)
            }
        }
        let next = timed
            .filter { $0.startAt > now }
            .min { ($0.startAt, $0.sortIndex, $0.id) < ($1.startAt, $1.sortIndex, $1.id) }
        return (nowIds, next?.id)
    }
}
