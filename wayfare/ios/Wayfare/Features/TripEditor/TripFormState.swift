import Foundation

/// Editable copy of a trip for the New / Edit Trip form.
struct TripFormState: Equatable {
    var title: String = ""
    var destination: String = ""
    var startDay: CalendarDay
    var endDay: CalendarDay
    var timeZone: String = TimeZone.current.identifier
    var coverEmoji: String = "✈️"
    var colorHex: String = CoverColor.lagoon.hex
    var notes: String = ""

    /// Set once the user picks a zone by hand, so destination search no longer overrides it.
    var timeZoneChosenManually = false
    /// Set once the user picks an emoji, so destination search no longer suggests a flag.
    var emojiChosenManually = false

    /// Defaults for a new trip: starts today + 14 days, lasts 5 days, device zone.
    static func newTrip(now: Date = Date(), zone: TimeZone = .current) -> TripFormState {
        let start = CalendarDay.today(in: zone, now: now).adding(days: 14)
        return TripFormState(startDay: start, endDay: start.adding(days: 4), timeZone: zone.identifier)
    }

    init(startDay: CalendarDay, endDay: CalendarDay, timeZone: String = TimeZone.current.identifier) {
        self.startDay = startDay
        self.endDay = endDay
        self.timeZone = timeZone
    }

    init(trip: Trip) {
        title = trip.title
        destination = trip.destination
        startDay = trip.startDay
        endDay = trip.endDay
        timeZone = trip.timeZone
        coverEmoji = trip.coverEmoji
        colorHex = trip.colorHex
        notes = trip.notes
        timeZoneChosenManually = true
        emojiChosenManually = true
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= 80 && endDay >= startDay
    }

    /// Moving Start past End keeps the trip length (UX spec 3.2).
    mutating func setStartDay(_ newStart: CalendarDay) {
        let length = max(0, startDay.days(to: endDay))
        startDay = newStart
        if endDay < newStart {
            endDay = newStart.adding(days: length)
        }
    }

    func apply(to trip: Trip) {
        trip.title = trimmedTitle
        trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.startDate = startDay.string
        trip.endDate = max(endDay, startDay).string
        trip.timeZone = TimeZone(identifier: timeZone) != nil ? timeZone : TimeZone.current.identifier
        trip.coverEmoji = coverEmoji.isEmpty ? "✈️" : coverEmoji
        trip.colorHex = HexColor.parse(colorHex) != nil ? colorHex.uppercased() : CoverColor.lagoon.hex
        trip.notes = notes
    }
}

enum EmojiText {
    /// Quick picks from design system 7.2.
    static let quickPicks = ["✈️", "🏖️", "🏔️", "🏙️", "🗺️", "🎒", "🚆", "🚗", "⛺️", "🍷", "🎿", "❤️"]

    /// True when `text` is exactly one grapheme cluster that renders as an emoji.
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        return isEmoji(character)
    }

    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Text-default emoji made emoji by VS16 (e.g. "✈️"), keycaps, and flags.
        if scalars.count > 1 && first.properties.isEmoji { return true }
        return false
    }

    /// The last emoji the user typed, or nil if the input had none.
    static func lastEmoji(in text: String) -> String? {
        text.last(where: { isEmoji($0) }).map { String($0) }
    }

    /// "PT" -> "🇵🇹".
    static func flag(forCountryCode code: String) -> String? {
        let letters = code.uppercased()
        guard letters.count == 2, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        var result = ""
        for scalar in letters.unicodeScalars {
            guard let flagScalar = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return nil }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }
}
