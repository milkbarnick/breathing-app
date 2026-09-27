import Foundation
import SwiftData

/// Sample "Lisbon & Porto" trip for #Preview blocks. Dates are relative to today, so previews show
/// an in-progress trip with Now/Next highlighting.
@MainActor
enum SampleData {
    static let userId = "5b0c7a4e-1f2d-4c3b-9a8e-000000000001"
    static let samId = "5b0c7a4e-1f2d-4c3b-9a8e-000000000002"
    static let tripId = "7d8e9f10-aaaa-4bbb-8ccc-000000000001"
    static let upcomingTripId = "7d8e9f10-aaaa-4bbb-8ccc-000000000002"
    static let flightId = "9a1b2c3d-0000-4000-8000-000000000001"
    static let hotelId = "9a1b2c3d-0000-4000-8000-000000000002"
    static let dinnerId = "9a1b2c3d-0000-4000-8000-000000000003"
    static let trainId = "9a1b2c3d-0000-4000-8000-000000000004"
    static let tourId = "9a1b2c3d-0000-4000-8000-000000000005"
    static let noteId = "9a1b2c3d-0000-4000-8000-000000000006"

    static let user = UserDTO(id: userId, displayName: "Nick", email: "x@privaterelay.appleid.com",
                              createdAt: 1_727_000_000_000)

    static let lisbon = "Europe/Lisbon"
    static let newYork = "America/New_York"

    /// Trip day 1 = yesterday in Lisbon, so "today" is day 2.
    static var startDay: CalendarDay {
        CalendarDay.today(in: TimeZone.resolve(lisbon)).adding(days: -1)
    }

    static func makeTrip() -> Trip {
        Trip(id: tripId, ownerId: userId, title: "Lisbon & Porto", destination: "Portugal",
             startDate: startDay.string, endDate: startDay.adding(days: 8).string, timeZone: lisbon,
             coverEmoji: "🇵🇹", colorHex: "#1E5FCC", notes: "Pastéis de nata at Manteigaria every day.",
             updatedAt: 1_727_000_000_000)
    }

    static func makeUpcomingTrip() -> Trip {
        let start = CalendarDay.today(in: .current).adding(days: 40)
        return Trip(id: upcomingTripId, ownerId: samId, title: "Kyoto in Autumn", destination: "Japan",
                    startDate: start.string, endDate: start.adding(days: 6).string, timeZone: "Asia/Tokyo",
                    coverEmoji: "🇯🇵", colorHex: "#A8326E", updatedAt: 1_727_000_000_000)
    }

    static func makeItems() -> [Item] {
        let lisbonZone = TimeZone.resolve(lisbon)
        let nyZone = TimeZone.resolve(newYork)
        let day1 = startDay
        let departure = day1.adding(days: -1).date(hour: 22, minute: 30, in: nyZone) ?? Date()
        let arrival = day1.date(hour: 9, minute: 45, in: lisbonZone) ?? Date()

        let flight = Item(
            id: flightId, tripId: tripId, kind: .flight, title: "TP 202 JFK → LIS",
            startAt: departure, endAt: arrival, startTimeZone: newYork, endTimeZone: lisbon,
            locationName: "JFK Terminal 1", latitude: 40.6413, longitude: -73.7781,
            confirmationCode: "ABC123",
            details: ["airline": "TAP", "flightNumber": "TP202", "fromCode": "JFK", "toCode": "LIS",
                      "terminal": "1", "seat": "14A"],
            reminderMinutes: 180, updatedBy: userId, updatedAt: 1_727_000_000_000)

        let hotel = Item(
            id: hotelId, tripId: tripId, kind: .lodging, title: "Memmo Alfama",
            startAt: day1.date(hour: 15, minute: 0, in: lisbonZone) ?? Date(),
            endAt: day1.adding(days: 4).date(hour: 11, minute: 0, in: lisbonZone),
            startTimeZone: lisbon, locationName: "Memmo Alfama",
            address: "Travessa das Merceeiras 27, 1100-348 Lisboa", latitude: 38.7110, longitude: -9.1305,
            confirmationCode: "MEM-88213",
            details: ["phone": "+351 21 049 5660", "roomType": "Deluxe, river view", "checkInTime": "from 15:00"],
            updatedBy: samId, updatedAt: 1_727_000_000_000)

        let dinner = Item(
            id: dinnerId, tripId: tripId, kind: .food, title: "Dinner at Taberna",
            startAt: day1.adding(days: 1).date(hour: 20, minute: 30, in: lisbonZone) ?? Date(),
            endAt: day1.adding(days: 1).date(hour: 22, minute: 30, in: lisbonZone),
            startTimeZone: lisbon, locationName: "Taberna da Rua das Flores",
            address: "Rua das Flores 103, Lisboa", latitude: 38.7106, longitude: -9.1433,
            details: ["partySize": "2", "phone": "+351 21 347 9418"], reminderMinutes: 60,
            updatedBy: samId, updatedAt: 1_727_000_000_000)

        let tour = Item(
            id: tourId, tripId: tripId, kind: .activity, title: "Tram 28 tour",
            startAt: day1.adding(days: 2).date(hour: 10, minute: 0, in: lisbonZone) ?? Date(),
            endAt: day1.adding(days: 2).date(hour: 12, minute: 0, in: lisbonZone),
            startTimeZone: lisbon, locationName: "Martim Moniz", latitude: 38.7166, longitude: -9.1360,
            details: ["partySize": "2", "bookingUrl": "https://example.com/tram28"], reminderMinutes: 60,
            updatedAt: 1_727_000_000_000)

        let train = Item(
            id: trainId, tripId: tripId, kind: .transport, title: "Train to Porto",
            startAt: day1.adding(days: 4).date(hour: 13, minute: 9, in: lisbonZone) ?? Date(),
            endAt: day1.adding(days: 4).date(hour: 16, minute: 5, in: lisbonZone),
            startTimeZone: lisbon, locationName: "Lisboa Santa Apolónia", latitude: 38.7137, longitude: -9.1227,
            confirmationCode: "CP4471",
            details: ["mode": "train", "operator": "CP Alfa Pendular", "fromName": "Lisboa Santa Apolónia",
                      "toName": "Porto Campanhã", "seat": "Car 4 · 62"],
            reminderMinutes: 60, updatedAt: 1_727_000_000_000)

        let note = Item(
            id: noteId, tripId: tripId, kind: .note, title: "Pick up SIM card",
            startAt: day1.startDate(in: lisbonZone) ?? Date(), startTimeZone: lisbon, allDay: true,
            notes: "Vodafone shop in the arrivals hall.\nBring passport.", updatedAt: 1_727_000_000_000)

        return [flight, hotel, dinner, tour, train, note]
    }

    static func makeMembers() -> [Member] {
        [
            Member(tripId: tripId, userId: userId, displayName: "Nick", role: .owner, updatedAt: 1),
            Member(tripId: tripId, userId: samId, displayName: "Sam", role: .editor, updatedAt: 1),
            Member(tripId: upcomingTripId, userId: samId, displayName: "Sam", role: .owner, updatedAt: 1),
            Member(tripId: upcomingTripId, userId: userId, displayName: "Nick", role: .viewer, updatedAt: 1),
        ]
    }

    /// Inserts the sample trip, items and members into `context`.
    static func insert(into context: ModelContext) {
        context.insert(makeTrip())
        context.insert(makeUpcomingTrip())
        makeItems().forEach { context.insert($0) }
        makeMembers().forEach { context.insert($0) }
        try? context.save()
    }

    /// An in-memory container with the sample data.
    static func container() -> ModelContainer {
        let services = AppServices.preview()
        return services.container
    }

    static var flightSnapshot: ItemSnapshot {
        makeItems()[0].snapshot
    }
}
