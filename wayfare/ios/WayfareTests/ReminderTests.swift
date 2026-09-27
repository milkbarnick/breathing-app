import XCTest
@testable import Wayfare

/// Reminder fire dates, copy, and the 60-notification cap (UX spec 4.1).
final class ReminderTests: XCTestCase {
    private let lisbon = TimeZone(identifier: "Europe/Lisbon")!
    private let enGB = Locale(identifier: "en_GB")

    private func instant(_ text: String) -> Date {
        JSONCoding.parseInstant(text) ?? Date.distantPast
    }

    private func flight(reminder: Int? = 180) -> ItemSnapshot {
        ItemSnapshot(id: "f1", tripId: "t1", kind: .flight, title: "TP 202 JFK → LIS",
                     startAt: instant("2026-10-02T02:30:00Z"), endAt: instant("2026-10-02T09:45:00Z"),
                     startTimeZone: "America/New_York", endTimeZone: "Europe/Lisbon",
                     locationName: "JFK Terminal 1", confirmationCode: "ABC123",
                     details: ["fromCode": "JFK", "toCode": "LIS", "terminal": "1", "seat": "14A"],
                     reminderMinutes: reminder)
    }

    // MARK: - Fire dates

    func testFireDateIsStartMinusMinutes() {
        let start = instant("2026-10-02T02:30:00Z")
        XCTAssertEqual(ReminderPlanner.fireDate(startAt: start, reminderMinutes: 180), instant("2026-10-01T23:30:00Z"))
        XCTAssertEqual(ReminderPlanner.fireDate(startAt: start, reminderMinutes: 0), start)
        XCTAssertEqual(ReminderPlanner.fireDate(startAt: start, reminderMinutes: 1440), instant("2026-10-01T02:30:00Z"))
        XCTAssertNil(ReminderPlanner.fireDate(startAt: start, reminderMinutes: nil))
        XCTAssertNil(ReminderPlanner.fireDate(startAt: start, reminderMinutes: -5))
    }

    func testFireDateIsIndependentOfDeviceZone() {
        // Instants in, instants out: a DST change or travel can't move the reminder.
        let start = instant("2026-10-25T09:00:00Z") // Lisbon DST ends Oct 25 2026
        XCTAssertEqual(ReminderPlanner.fireDate(startAt: start, reminderMinutes: 120), instant("2026-10-25T07:00:00Z"))
    }

    func testPlanSkipsItemsWithoutReminderAndPastReminders() {
        let now = instant("2026-10-01T00:00:00Z")
        let items = [
            flight(reminder: 180),
            ItemSnapshot(id: "none", tripId: "t1", kind: .note, title: "No reminder",
                         startAt: instant("2026-10-03T10:00:00Z"), startTimeZone: "Europe/Lisbon"),
            ItemSnapshot(id: "past", tripId: "t1", kind: .food, title: "Past",
                         startAt: instant("2026-09-30T20:00:00Z"), startTimeZone: "Europe/Lisbon", reminderMinutes: 60),
        ]
        let plan = ReminderPlanner.plan(items: items, now: now, deviceZone: lisbon, locale: enGB)
        XCTAssertEqual(plan.map(\.identifier), ["item-f1"])
        XCTAssertEqual(plan.first?.tripId, "t1")
        XCTAssertEqual(plan.first?.hasConfirmationCode, true)
    }

    // MARK: - Copy

    func testFlightBody() {
        let body = ReminderPlanner.body(for: flight(), deviceZone: lisbon, locale: enGB)
        XCTAssertTrue(body.hasPrefix("Departs 22:30"), body)
        XCTAssertTrue(body.contains(" from JFK · Terminal 1 · Seat 14A."), body)
        XCTAssertTrue(body.hasSuffix("Confirmation ABC123."), body)
    }

    func testNoZoneSuffixWhenDeviceIsInItemZone() {
        let body = ReminderPlanner.body(for: flight(), deviceZone: TimeZone(identifier: "America/New_York")!, locale: enGB)
        XCTAssertTrue(body.hasPrefix("Departs 22:30 from JFK"), body)
    }

    func testNowPrefixAndEmptySegments() {
        let dinner = ItemSnapshot(id: "d", tripId: "t", kind: .food, title: "Dinner",
                                  startAt: instant("2026-10-03T19:30:00Z"), startTimeZone: "Europe/Lisbon",
                                  details: ["partySize": "4"], reminderMinutes: 0)
        XCTAssertEqual(ReminderPlanner.body(for: dinner, deviceZone: lisbon, locale: enGB), "Now: Table for 4 at 20:30.")

        let activity = ItemSnapshot(id: "a", tripId: "t", kind: .activity, title: "Tram 28",
                                    startAt: instant("2026-10-03T09:00:00Z"), startTimeZone: "Europe/Lisbon",
                                    locationName: "Martim Moniz", reminderMinutes: 60)
        XCTAssertEqual(ReminderPlanner.body(for: activity, deviceZone: lisbon, locale: enGB), "Starts at 10:00 · Martim Moniz.")

        let note = ItemSnapshot(id: "n", tripId: "t", kind: .note, title: "SIM",
                                startAt: instant("2026-10-03T09:00:00Z"), startTimeZone: "Europe/Lisbon",
                                reminderMinutes: 15)
        XCTAssertEqual(ReminderPlanner.body(for: note, deviceZone: lisbon, locale: enGB), "10:00")
    }

    // MARK: - The 60 cap

    private func reminder(_ id: String, fireIn hours: Double, from now: Date) -> PlannedReminder {
        PlannedReminder(identifier: "item-\(id)", itemId: id, tripId: "t", fireDate: now.addingTimeInterval(hours * 3600),
                        title: id, body: "", hasConfirmationCode: false)
    }

    func testCapKeepsTheSoonestSixty() {
        let now = instant("2026-10-01T00:00:00Z")
        // 100 reminders, one per hour, in shuffled order.
        let all = (0..<100).map { reminder(String(format: "%03d", $0), fireIn: Double($0 + 1), from: now) }.shuffled()
        let selected = ReminderPlanner.selectSoonest(all, now: now)
        XCTAssertEqual(ReminderPlanner.maxPending, 60)
        XCTAssertEqual(selected.count, 60)
        XCTAssertEqual(selected.first?.itemId, "000")
        XCTAssertEqual(selected.last?.itemId, "059")
        XCTAssertEqual(selected.map(\.fireDate), selected.map(\.fireDate).sorted())
    }

    func testCapDropsPastAndBeyondHorizon() {
        let now = instant("2026-10-01T00:00:00Z")
        let reminders = [
            reminder("past", fireIn: -1, from: now),
            reminder("now", fireIn: 0, from: now),
            reminder("soon", fireIn: 2, from: now),
            reminder("edge", fireIn: 24 * 60, from: now),        // exactly 60 days: kept
            reminder("far", fireIn: 24 * 60 + 1, from: now),     // beyond 60 days: dropped
        ]
        let selected = ReminderPlanner.selectSoonest(reminders, now: now)
        XCTAssertEqual(selected.map(\.itemId), ["soon", "edge"])
    }

    func testCapTiesAreStable() {
        let now = instant("2026-10-01T00:00:00Z")
        let reminders = ["b", "a", "c"].map { reminder($0, fireIn: 5, from: now) }
        XCTAssertEqual(ReminderPlanner.selectSoonest(reminders, now: now, limit: 2).map(\.itemId), ["a", "b"])
    }

    func testIdentifiersAreStableAndLowercase() {
        XCTAssertEqual(ReminderPlanner.identifier(for: "ABC-123"), "item-abc-123")
    }

    // MARK: - Reminder labels

    func testReminderLabels() {
        XCTAssertEqual(TimeFormat.reminderLabel(nil), "None")
        XCTAssertEqual(TimeFormat.reminderLabel(0), "At time of event")
        XCTAssertEqual(TimeFormat.reminderLabel(15), "15 min before")
        XCTAssertEqual(TimeFormat.reminderLabel(60), "1 hour before")
        XCTAssertEqual(TimeFormat.reminderLabel(180), "3 hours before")
        XCTAssertEqual(TimeFormat.reminderLabel(2880), "2 days before")
    }
}
