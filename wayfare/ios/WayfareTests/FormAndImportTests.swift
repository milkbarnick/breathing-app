import XCTest
@testable import Wayfare

/// Item form rules and AI import review heuristics.
final class FormAndImportTests: XCTestCase {
    private let lisbon = TimeZone(identifier: "Europe/Lisbon")!
    private let day = CalendarDay(year: 2026, month: 10, day: 3)

    private func instant(_ text: String) -> Date {
        JSONCoding.parseInstant(text) ?? Date.distantPast
    }

    func testNewFormDefaults() {
        let lodging = ItemFormState.new(kind: .lodging, tripZone: "Europe/Lisbon", day: day)
        XCTAssertEqual(lodging.startAt, instant("2026-10-03T14:00:00Z")) // 15:00 Lisbon
        XCTAssertEqual(lodging.endAt, instant("2026-10-04T10:00:00Z"))   // 11:00 next day
        XCTAssertNil(lodging.reminderMinutes)

        let flight = ItemFormState.new(kind: .flight, tripZone: "Europe/Lisbon", day: day)
        XCTAssertEqual(flight.reminderMinutes, 180)
        XCTAssertEqual(flight.startAt, instant("2026-10-03T08:00:00Z"))   // 09:00 Lisbon

        let note = ItemFormState.new(kind: .note, tripZone: "Europe/Lisbon", day: day)
        XCTAssertTrue(note.allDay)
    }

    func testFlightAutoTitleAndValidation() {
        var form = ItemFormState.new(kind: .flight, tripZone: "Europe/Lisbon", day: day)
        XCTAssertFalse(form.isValid, "title required")
        form.setDetail("flightNumber", "TP202")
        form.setDetail("fromCode", "JFK")
        form.setDetail("toCode", "LIS")
        XCTAssertEqual(form.effectiveTitle, "TP202 JFK → LIS")
        XCTAssertTrue(form.isValid)

        form.endAt = form.startAt.addingTimeInterval(-60)
        XCTAssertEqual(form.endError, "Arrival must be after departure.")
        XCTAssertFalse(form.isValid)
    }

    func testEndIsComparedAsInstantNotWallClock() {
        // Departs 22:30 New York, arrives 09:45 Lisbon: wall clock goes "backwards", the instant doesn't.
        var form = ItemFormState(kind: .flight, startAt: instant("2026-10-02T02:30:00Z"), startTimeZone: "America/New_York")
        form.title = "TP 202"
        form.endAt = instant("2026-10-02T09:45:00Z")
        form.endTimeZone = "Europe/Lisbon"
        XCTAssertNil(form.endError)
    }

    func testKindChangeDropsOtherKindsDetailsOnSave() {
        var form = ItemFormState.new(kind: .flight, tripZone: "Europe/Lisbon", day: day)
        form.title = "Something"
        form.setDetail("seat", "14A")
        form.setDetail("gate", "B12")
        form.setDetail("customKey", "kept")
        form.kind = .food
        XCTAssertEqual(form.cleanedDetails, ["customKey": "kept"])
    }

    func testAllDayIsStoredAtLocalMidnight() {
        var form = ItemFormState(kind: .note, startAt: instant("2026-10-03T15:42:00Z"), startTimeZone: "Europe/Lisbon")
        form.allDay = true
        XCTAssertEqual(form.normalizedStart, instant("2026-10-02T23:00:00Z")) // Oct 3 00:00 Lisbon
    }

    func testWallClockIsKeptWhenZoneChanges() {
        let tenLisbon = instant("2026-10-03T09:00:00Z")
        let moved = WallClock.keeping(tenLisbon, from: lisbon, to: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(moved, instant("2026-10-03T14:00:00Z")) // 10:00 EDT
        XCTAssertEqual(WallClock.airportCode(in: "John F. Kennedy International Airport (JFK)"), "JFK")
        XCTAssertNil(WallClock.airportCode(in: "Lisbon Airport"))
    }

    // MARK: - Import review

    private func draft(_ json: String) throws -> ItemDraftDTO {
        try JSONCoding.makeDecoder().decode(ItemDraftDTO.self, from: Data(json.utf8))
    }

    func testImportWarningsAndDuplicates() throws {
        let trip = ImportReview.TripContext(start: CalendarDay(year: 2026, month: 10, day: 1),
                                            end: CalendarDay(year: 2026, month: 10, day: 9),
                                            timeZone: "Europe/Lisbon")
        let existing = [
            ItemSnapshot(id: "x", tripId: "t", kind: .flight, title: "TP 202 JFK → LIS",
                         startAt: instant("2026-10-02T02:30:00Z"), startTimeZone: "America/New_York",
                         confirmationCode: "ABC123"),
        ]
        let drafts = [
            try draft(#"{ "kind": "flight", "title": "TP202", "startAt": "2026-10-02T02:30:00Z", "startTimeZone": "America/New_York", "confirmationCode": "abc123" }"#),
            try draft(#"{ "kind": "lodging", "title": "Hotel", "startAt": "2026-10-12T14:00:00Z", "startTimeZone": "Mars/Base" }"#),
        ]
        let rows = ImportReview.rows(from: drafts, trip: trip, existing: existing)
        XCTAssertEqual(rows.count, 2)

        XCTAssertFalse(rows[0].included, "duplicates default to unchecked")
        XCTAssertTrue(rows[0].warnings.contains("Possible duplicate of “TP 202 JFK → LIS”"))
        XCTAssertTrue(rows[0].warnings.contains("Arrival time missing"))

        XCTAssertTrue(rows[1].included)
        XCTAssertEqual(rows[1].form.startTimeZone, "Europe/Lisbon", "invalid zones fall back to the trip zone")
        XCTAssertTrue(rows[1].warnings.contains("Check the time zone"))
        XCTAssertTrue(rows[1].warnings.contains("Check-out missing"))
        XCTAssertTrue(rows[1].warnings.contains(where: { $0.hasPrefix("Outside trip dates") }))
    }

    func testEmojiAndFlags() {
        XCTAssertEqual(EmojiText.flag(forCountryCode: "pt"), "🇵🇹")
        XCTAssertTrue(EmojiText.isSingleEmoji("✈️"))
        XCTAssertTrue(EmojiText.isSingleEmoji("🇵🇹"))
        XCTAssertFalse(EmojiText.isSingleEmoji("A"))
        XCTAssertFalse(EmojiText.isSingleEmoji("1"))
        XCTAssertEqual(EmojiText.lastEmoji(in: "abc🏖️"), "🏖️")
    }

    func testHexColors() {
        XCTAssertEqual(HexColor.parse("#0A6B7C"), 0x0A6B7C)
        XCTAssertEqual(HexColor.parse("2f6feb"), 0x2F6FEB)
        XCTAssertNil(HexColor.parse("#12345"))
        XCTAssertNil(HexColor.parse("#GGGGGG"))
    }
}
