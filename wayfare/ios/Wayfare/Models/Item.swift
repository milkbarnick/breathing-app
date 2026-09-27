import Foundation
import SwiftData

/// An itinerary entry, stored locally with SwiftData and synced with `/v1/trips/:id/items` and `/v1/sync`.
@Model
final class Item {
    /// Lowercase UUID string, generated on the device for new items.
    @Attribute(.unique) var id: String
    var tripId: String
    /// Raw `ItemKind` value. Use `kind` in code.
    var kindRaw: String
    var title: String
    var startAt: Date
    var endAt: Date?
    var startTimeZone: String
    var endTimeZone: String?
    var allDay: Bool
    var locationName: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var confirmationCode: String
    /// Free-form string map from the contract (`details`), stored as a Codable value.
    var details: [String: String]
    var notes: String
    var reminderMinutes: Int?
    var sortIndex: Int
    var updatedBy: String?

    // MARK: Local sync state
    /// Server `updatedAt` in ms since epoch. 0 means the server has never acknowledged this row.
    var updatedAt: Int
    var needsPush: Bool
    var pendingDelete: Bool
    var localRevision: Int

    init(
        id: String = UUID().uuidString.lowercased(),
        tripId: String,
        kind: ItemKind,
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        startTimeZone: String,
        endTimeZone: String? = nil,
        allDay: Bool = false,
        locationName: String = "",
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        confirmationCode: String = "",
        details: [String: String] = [:],
        notes: String = "",
        reminderMinutes: Int? = nil,
        sortIndex: Int = 0,
        updatedBy: String? = nil,
        updatedAt: Int = 0,
        needsPush: Bool = false,
        pendingDelete: Bool = false,
        localRevision: Int = 0
    ) {
        self.id = id.lowercased()
        self.tripId = tripId.lowercased()
        self.kindRaw = kind.rawValue
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.startTimeZone = startTimeZone
        self.endTimeZone = endTimeZone
        self.allDay = allDay
        self.locationName = locationName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.confirmationCode = confirmationCode
        self.details = details
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.sortIndex = sortIndex
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
        self.needsPush = needsPush
        self.pendingDelete = pendingDelete
        self.localRevision = localRevision
    }
}

extension Item {
    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    func markEdited() {
        needsPush = true
        localRevision += 1
    }

    /// An immutable value copy for pure logic (grouping, reminders) and for views.
    var snapshot: ItemSnapshot {
        ItemSnapshot(
            id: id, tripId: tripId, kind: kind, title: title,
            startAt: startAt, endAt: endAt,
            startTimeZone: startTimeZone, endTimeZone: endTimeZone,
            allDay: allDay, locationName: locationName, address: address,
            latitude: latitude, longitude: longitude,
            confirmationCode: confirmationCode, details: details, notes: notes,
            reminderMinutes: reminderMinutes, sortIndex: sortIndex,
            updatedBy: updatedBy, isUnsynced: needsPush
        )
    }
}
