import XCTest
@testable import Wayfare

/// Day grouping across time zones, midnight, the date line and lodging stays (UX spec 3.3.1, 5.1).
final class DayGroupingTests: XCTestCase {
    private let lisbon = TimeZone(identifier: "Europe/Lisbon")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let london = TimeZone(identifier: "Europe/London")!
    private let sydney = TimeZone(identifier: "Australia/Sydney")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let enUS = Locale(identifier: "en_US")

    private let tripStart = CalendarDay(year: 2026, month: 10, day: 1)
    private let tripEnd = CalendarDay(year: 2026, month: 10, day: 9)

    private func instant(_ text: String) -> Date {
        JSONCoding.parseInstant(text) ?? Date.distantPast
    }

    private func item(_ id: String, _ kind: ItemKind = .activity, start: String, end: String? = nil,
                      zone: String = "Europe/Lisbon", endZone: String? = nil, allDay: Bool = false,
                      sortIndex: Int = 0, title: String? = nil) -> ItemSnapshot {
        ItemSnapshot(id: id, tripId: "trip", kind: kind, title: title ?? id, startAt: instant(start),
                     endAt: end.map(instant), startTimeZone: zone, endTimeZone: endZone, allDay: allDay,
                     sortIndex: sortIndex)
    }

    // MARK: - Calendar days

    func testCalendarDayParsing() {
        XCTAssertEqual(CalendarDay(string: "2026-10-01"), CalendarDay(year: 2026, month: 10, day: 1))
        XCTAssertNil(CalendarDay(string: "2026-02-30"))
        XCTAssertNil(CalendarDay(string: "2026-10-1"))
        XCTAssertNil(CalendarDay(string: "not a date"))
        XCTAssertEqual(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1).string, "2027-01-01")
        XCTAssertEqual(tripStart.days(to: tripEnd), 8)
    }

    // MARK: - Grouping in the trip zone

    func testLateNightNewYorkDepartureGroupsUnderNextLisbonDay() {
        // 22:30 EDT on Oct 1 is 03:30 on Oct 2 in Lisbon.
        let flight = item("flight", .flight, start: "2026-10-02T02:30:00Z", end: "2026-10-02T09:45:00Z",
                          zone: "America/New_York", endZone: "Europe/Lisbon")
        XCTAssertEqual(DayGrouping.groupingDay(for: flight, tripZone: lisbon), CalendarDay(year: 2026, month: 10, day: 2))

        // The badge keeps the ticket's local date and zone visible.
        let badge = TimeFormat.zoneBadge(for: flight.startAt, itemZone: newYork, tripZone: lisbon,
                                         sectionDay: CalendarDay(year: 2026, month: 10, day: 2), locale: enUS)
        XCTAssertNotNil(badge)
        XCTAssertTrue(badge?.hasPrefix("Oct 1 · ") ?? false, "got \(badge ?? "nil")")
    }

    func testMidnightBoundaryInTripZone() {
        // 23:59 and 00:01 Lisbon time (UTC+1 in October) land on consecutive days.
        let beforeMidnight = item("a", start: "2026-10-03T22:59:00Z")
        let afterMidnight = item("b", start: "2026-10-03T23:01:00Z")
        XCTAssertEqual(DayGrouping.groupingDay(for: beforeMidnight, tripZone: lisbon), CalendarDay(year: 2026, month: 10, day: 3))
        XCTAssertEqual(DayGrouping.groupingDay(for: afterMidnight, tripZone: lisbon), CalendarDay(year: 2026, month: 10, day: 4))
    }

    func testAllDayItemKeepsItsOwnLocalDate() {
        // Local midnight Oct 5 in Tokyo is Oct 4 15:00 UTC, i.e. Oct 4 in Lisbon. All-day must not drift.
        let note = item("note", .note, start: "2026-10-04T15:00:00Z", zone: "Asia/Tokyo", allDay: true)
        XCTAssertEqual(DayGrouping.groupingDay(for: note, tripZone: lisbon), CalendarDay(year: 2026, month: 10, day: 5))
    }

    func testSectionsIncludeEmptyDaysAndBeforeAfter() {
        let items = [
            item("pre", .lodging, start: "2026-09-30T20:00:00Z"),          // Sep 30 in Lisbon
            item("mid", start: "2026-10-04T10:00:00Z"),
            item("post", start: "2026-10-11T10:00:00Z"),                   // Oct 11
        ]
        let sections = DayGrouping.sections(items: items, tripStart: tripStart, tripEnd: tripEnd, tripZone: lisbon)
        XCTAssertEqual(sections.count, 9 + 2)
        XCTAssertEqual(sections.first?.placement, .beforeTrip)
        XCTAssertEqual(sections.first?.day, CalendarDay(year: 2026, month: 9, day: 30))
        XCTAssertEqual(sections.last?.placement, .afterTrip)
        XCTAssertEqual(sections.last?.day, CalendarDay(year: 2026, month: 10, day: 11))
        XCTAssertEqual(sections[1].placement, .trip(dayNumber: 1))
        XCTAssertTrue(sections[1].rows.isEmpty, "empty trip days are kept")
        XCTAssertEqual(sections[4].rows.map(\.item.id), ["mid"])
    }

    func testSingleDayTrip() {
        let sections = DayGrouping.sections(items: [], tripStart: tripStart, tripEnd: tripStart, tripZone: lisbon)
        XCTAssertEqual(sections.count, 1)
    }

    func testRowOrderBandsThenAllDayThenTimed() {
        let hotel = item("hotel", .lodging, start: "2026-10-01T14:00:00Z", end: "2026-10-04T10:00:00Z")
        let dinner = item("dinner", .food, start: "2026-10-02T19:30:00Z")
        let breakfast = item("breakfast", .food, start: "2026-10-02T07:30:00Z")
        let note = item("note", .note, start: "2026-10-01T23:00:00Z", allDay: true) // Oct 2 00:00 Lisbon
        let sections = DayGrouping.sections(items: [dinner, hotel, breakfast, note], tripStart: tripStart,
                                            tripEnd: tripEnd, tripZone: lisbon)
        let day2 = sections[1]
        XCTAssertEqual(day2.day, CalendarDay(year: 2026, month: 10, day: 2))
        XCTAssertEqual(day2.rows.map(\.item.id), ["hotel", "note", "breakfast", "dinner"])
        XCTAssertTrue(day2.rows[0].isBand)
    }

    // MARK: - Lodging

    func testLodgingExpandsIntoCheckInStayingAndCheckOut() {
        let hotel = item("hotel", .lodging, start: "2026-10-01T14:00:00Z", end: "2026-10-04T10:00:00Z")
        let rows = DayGrouping.rows(for: hotel, tripZone: lisbon)
        XCTAssertEqual(rows.map(\.role), [
            .checkIn(nights: 3),
            .staying(night: 2, of: 3),
            .staying(night: 3, of: 3),
            .checkOut,
        ])
        XCTAssertEqual(rows.map(\.day.day), [1, 2, 3, 4])
        XCTAssertEqual(TimelineRowText.subtitle(for: rows[0]), "Check-in · 3 nights")
        XCTAssertEqual(TimelineRowText.subtitle(for: rows[3]), "Check-out")
    }

    func testLodgingWithoutCheckOutShowsOnlyCheckIn() {
        let hotel = item("hotel", .lodging, start: "2026-10-01T14:00:00Z")
        let rows = DayGrouping.rows(for: hotel, tripZone: lisbon)
        XCTAssertEqual(rows.map(\.role), [.checkIn(nights: 0)])
        XCTAssertEqual(TimelineRowText.subtitle(for: rows[0]), "Check-in")
    }

    func testStayingBandsNeverCreateSections() {
        // A stay that runs past the trip end adds an After section for the check-out day only.
        let hotel = item("hotel", .lodging, start: "2026-10-07T14:00:00Z", end: "2026-10-12T10:00:00Z")
        let sections = DayGrouping.sections(items: [hotel], tripStart: tripStart, tripEnd: tripEnd, tripZone: lisbon)
        XCTAssertEqual(sections.filter { $0.placement == .afterTrip }.map(\.day.day), [12])
    }

    // MARK: - Day offsets and zone badges

    func testOvernightFlightIsPlusOne() {
        let offset = TimeFormat.dayOffset(start: instant("2026-10-02T02:30:00Z"), startZone: newYork,
                                          end: instant("2026-10-02T09:45:00Z"), endZone: lisbon)
        XCTAssertEqual(offset, 1)
        XCTAssertEqual(TimeFormat.dayOffsetSuffix(offset), "+1")
    }

    func testEastboundDateLineIsMinusOne() {
        // SYD Oct 2 01:00 (AEST) → LAX Oct 1 21:00 (PDT).
        let offset = TimeFormat.dayOffset(start: instant("2026-10-01T15:00:00Z"), startZone: sydney,
                                          end: instant("2026-10-02T04:00:00Z"), endZone: losAngeles)
        XCTAssertEqual(offset, -1)
        XCTAssertEqual(TimeFormat.dayOffsetSuffix(offset), "\u{2212}1")
    }

    func testWestboundDateLineIsPlusTwo() {
        // LAX Oct 1 22:30 (PDT) → SYD Oct 3 06:30 (AEST).
        let offset = TimeFormat.dayOffset(start: instant("2026-10-02T05:30:00Z"), startZone: losAngeles,
                                          end: instant("2026-10-02T20:30:00Z"), endZone: sydney)
        XCTAssertEqual(offset, 2)
    }

    func testNoZoneBadgeWhenOffsetsMatch() {
        // Lisbon and London share UTC+1 in October: compare offsets, not identifiers.
        let date = instant("2026-10-03T12:00:00Z")
        XCTAssertNil(TimeFormat.zoneBadge(for: date, itemZone: london, tripZone: lisbon, sectionDay: nil))
        XCTAssertNotNil(TimeFormat.zoneBadge(for: date, itemZone: newYork, tripZone: lisbon, sectionDay: nil))
    }

    func testDurationComesFromInstants() {
        XCTAssertEqual(TimeFormat.duration(from: instant("2026-10-02T02:30:00Z"), to: instant("2026-10-02T09:45:00Z")),
                       "7 h 15 min")
    }

    // MARK: - Now / Next and trip phase

    func testNowAndNext() {
        let items = [
            item("breakfast", start: "2026-10-03T07:00:00Z", end: "2026-10-03T08:00:00Z"),
            item("museum", start: "2026-10-03T09:00:00Z", end: "2026-10-03T11:00:00Z"),
            item("lunch", start: "2026-10-03T12:00:00Z"),
            item("dinner", start: "2026-10-03T19:00:00Z"),
            item("hotel", .lodging, start: "2026-10-01T14:00:00Z", end: "2026-10-05T10:00:00Z"),
        ]
        let result = NowNext.compute(items: items, now: instant("2026-10-03T10:00:00Z"))
        XCTAssertEqual(result.now, ["museum"], "lodging is never Now")
        XCTAssertEqual(result.next, "lunch")
    }

    func testTripPhaseUsesTripZone() {
        // 23:30 UTC on Oct 9 is already Oct 10 in Lisbon: the trip is past there.
        let now = instant("2026-10-09T23:30:00Z")
        XCTAssertEqual(TripPhase.of(start: tripStart, end: tripEnd, timeZone: lisbon, now: now), .past)
        XCTAssertEqual(TripPhase.of(start: tripStart, end: tripEnd, timeZone: newYork, now: now),
                       .inProgress(dayNumber: 9, totalDays: 9))
        XCTAssertEqual(TripPhase.of(start: tripStart, end: tripEnd, timeZone: lisbon, now: instant("2026-09-19T12:00:00Z")),
                       .upcoming(daysUntil: 12))
    }

    func testCountdownCopy() {
        XCTAssertEqual(TimeFormat.countdown(daysUntil: 1), "Tomorrow")
        XCTAssertEqual(TimeFormat.countdown(daysUntil: 12), "in 12 days")
        XCTAssertEqual(TimeFormat.countdown(daysUntil: 21), "in 3 wks")
        XCTAssertEqual(TimeFormat.countdown(daysUntil: 120), "in 4 mo")
    }
}
