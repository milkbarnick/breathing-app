import Foundation
import SwiftData

/// A trip, stored locally with SwiftData and synced with `/v1/trips` and `/v1/sync`.
@Model
final class Trip {
    /// Lowercase UUID string, generated on the device for new trips.
    @Attribute(.unique) var id: String
    var ownerId: String
    var title: String
    var destination: String
    /// "YYYY-MM-DD".
    var startDate: String
    /// "YYYY-MM-DD".
    var endDate: String
    /// IANA identifier, e.g. "Europe/Lisbon".
    var timeZone: String
    var coverEmoji: String
    var colorHex: String
    var notes: String

    // MARK: Local sync state
    /// Server `updatedAt` in ms since epoch. 0 means the server has never acknowledged this row.
    var updatedAt: Int
    /// True while there are local changes the server hasn't acknowledged.
    var needsPush: Bool
    /// True when the user deleted (owner) or left (member) the trip and the server hasn't confirmed yet.
    var pendingDelete: Bool
    /// Bumped on every local edit, so a push that raced with a newer edit doesn't clear `needsPush`.
    var localRevision: Int

    init(
        id: String = UUID().uuidString.lowercased(),
        ownerId: String = "",
        title: String = "",
        destination: String = "",
        startDate: String,
        endDate: String,
        timeZone: String = TimeZone.current.identifier,
        coverEmoji: String = "✈️",
        colorHex: String = CoverColor.lagoon.hex,
        notes: String = "",
        updatedAt: Int = 0,
        needsPush: Bool = false,
        pendingDelete: Bool = false,
        localRevision: Int = 0
    ) {
        self.id = id.lowercased()
        self.ownerId = ownerId.lowercased()
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.timeZone = timeZone
        self.coverEmoji = coverEmoji
        self.colorHex = colorHex
        self.notes = notes
        self.updatedAt = updatedAt
        self.needsPush = needsPush
        self.pendingDelete = pendingDelete
        self.localRevision = localRevision
    }
}

extension Trip {
    var tz: TimeZone { TimeZone.resolve(timeZone) }

    var startDay: CalendarDay {
        CalendarDay(string: startDate) ?? CalendarDay.today(in: tz)
    }

    /// Never earlier than `startDay`, even if the stored value is inconsistent.
    var endDay: CalendarDay {
        let end = CalendarDay(string: endDate) ?? startDay
        return max(end, startDay)
    }

    var displayTitle: String { title.isEmpty ? "Untitled trip" : title }

    /// Marks a local edit that must be pushed.
    func markEdited() {
        needsPush = true
        localRevision += 1
    }

    func phase(now: Date = Date()) -> TripPhase {
        TripPhase.of(start: startDay, end: endDay, timeZone: tz, now: now)
    }
}
