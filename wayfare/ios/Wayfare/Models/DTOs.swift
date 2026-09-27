import Foundation

// Codable types that mirror docs/api-contract.md exactly (camelCase keys).
// Decoders are lenient about missing optional text (they default to ""), because a
// sync must never fail on one odd row. Encoders send explicit `null`s for optional
// writable fields, so a PUT is always a full replace.

// MARK: - User and auth

struct UserDTO: Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var email: String?
    var createdAt: Int

    init(id: String, displayName: String, email: String?, createdAt: Int) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email)
        createdAt = try c.decodeIfPresent(Int.self, forKey: .createdAt) ?? 0
    }
}

struct AppleAuthRequest: Encodable, Equatable, Sendable {
    var identityToken: String
    var authorizationCode: String?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case identityToken, authorizationCode, displayName
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identityToken, forKey: .identityToken)
        try c.encode(authorizationCode, forKey: .authorizationCode)
        try c.encode(displayName, forKey: .displayName)
    }
}

struct AuthResponseDTO: Decodable, Sendable {
    var token: String
    var user: UserDTO
}

struct UpdateMeRequest: Encodable, Sendable {
    var displayName: String
}

/// Body of `POST /v1/auth/logout`. Sent only when the device has an APNs token.
struct LogoutRequest: Encodable, Sendable {
    var apnsToken: String
}

struct HealthDTO: Decodable, Sendable {
    var ok: Bool
    var version: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        if let text = try? c.decode(String.self, forKey: .version) {
            version = text
        } else if let number = try? c.decode(Int.self, forKey: .version) {
            version = String(number)
        } else {
            version = "?"
        }
    }

    enum CodingKeys: String, CodingKey { case ok, version }
}

// MARK: - Trip

struct TripDTO: Codable, Equatable, Sendable {
    var id: String
    var ownerId: String
    var title: String
    var destination: String
    var startDate: String
    var endDate: String
    var timeZone: String
    var coverEmoji: String
    var colorHex: String
    var notes: String
    var updatedAt: Int
    var deletedAt: Int?

    init(id: String, ownerId: String, title: String, destination: String, startDate: String, endDate: String,
         timeZone: String, coverEmoji: String, colorHex: String, notes: String, updatedAt: Int, deletedAt: Int?) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.timeZone = timeZone
        self.coverEmoji = coverEmoji
        self.colorHex = colorHex
        self.notes = notes
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        ownerId = (try c.decodeIfPresent(String.self, forKey: .ownerId) ?? "").lowercased()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? "UTC"
        coverEmoji = try c.decodeIfPresent(String.self, forKey: .coverEmoji) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? CoverColor.lagoon.hex
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        deletedAt = try c.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

/// The client-writable Trip fields for `PUT /v1/trips/:tripId`.
struct TripWriteDTO: Encodable, Equatable, Sendable {
    var title: String
    var destination: String
    var startDate: String
    var endDate: String
    var timeZone: String
    var coverEmoji: String
    var colorHex: String
    var notes: String
}

// MARK: - Item

struct ItemDTO: Codable, Equatable, Sendable {
    var id: String
    var tripId: String
    var kind: String
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
    var details: [String: String]
    var notes: String
    var reminderMinutes: Int?
    var sortIndex: Int
    var updatedAt: Int
    var updatedBy: String?
    var deletedAt: Int?

    init(id: String, tripId: String, kind: String, title: String, startAt: Date, endAt: Date?,
         startTimeZone: String, endTimeZone: String?, allDay: Bool, locationName: String, address: String,
         latitude: Double?, longitude: Double?, confirmationCode: String, details: [String: String],
         notes: String, reminderMinutes: Int?, sortIndex: Int, updatedAt: Int, updatedBy: String?,
         deletedAt: Int?) {
        self.id = id
        self.tripId = tripId
        self.kind = kind
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
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        tripId = try c.decode(String.self, forKey: .tripId).lowercased()
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ItemKind.note.rawValue
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startAt = try c.decode(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        startTimeZone = try c.decodeIfPresent(String.self, forKey: .startTimeZone) ?? "UTC"
        endTimeZone = try c.decodeIfPresent(String.self, forKey: .endTimeZone)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        confirmationCode = try c.decodeIfPresent(String.self, forKey: .confirmationCode) ?? ""
        details = try c.decodeIfPresent([String: String].self, forKey: .details) ?? [:]
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)?.lowercased()
        deletedAt = try c.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

/// The client-writable Item fields for `PUT /v1/trips/:tripId/items/:itemId`
/// (everything except updatedAt, updatedBy, deletedAt).
struct ItemWriteDTO: Encodable, Equatable, Sendable {
    var id: String
    var tripId: String
    var kind: String
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
    var details: [String: String]
    var notes: String
    var reminderMinutes: Int?
    var sortIndex: Int

    enum CodingKeys: String, CodingKey {
        case id, tripId, kind, title, startAt, endAt, startTimeZone, endTimeZone, allDay, locationName, address
        case latitude, longitude, confirmationCode, details, notes, reminderMinutes, sortIndex
    }

    /// Explicit so optional fields go out as `null` rather than being omitted.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripId, forKey: .tripId)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(startAt, forKey: .startAt)
        try c.encode(endAt, forKey: .endAt)
        try c.encode(startTimeZone, forKey: .startTimeZone)
        try c.encode(endTimeZone, forKey: .endTimeZone)
        try c.encode(allDay, forKey: .allDay)
        try c.encode(locationName, forKey: .locationName)
        try c.encode(address, forKey: .address)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(confirmationCode, forKey: .confirmationCode)
        try c.encode(details, forKey: .details)
        try c.encode(notes, forKey: .notes)
        try c.encode(reminderMinutes, forKey: .reminderMinutes)
        try c.encode(sortIndex, forKey: .sortIndex)
    }
}

/// An AI import draft: the Item writable fields minus id, tripId, sortIndex. Decoded leniently
/// because it comes from a language model via the server.
struct ItemDraftDTO: Decodable, Equatable, Sendable {
    var kind: String
    var title: String
    var startAt: Date?
    var endAt: Date?
    var startTimeZone: String?
    var endTimeZone: String?
    var allDay: Bool
    var locationName: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var confirmationCode: String
    var details: [String: String]
    var notes: String
    var reminderMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case kind, title, startAt, endAt, startTimeZone, endTimeZone, allDay, locationName, address
        case latitude, longitude, confirmationCode, details, notes, reminderMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ItemKind.note.rawValue
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startAt = try? c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try? c.decodeIfPresent(Date.self, forKey: .endAt)
        startTimeZone = try? c.decodeIfPresent(String.self, forKey: .startTimeZone)
        endTimeZone = try? c.decodeIfPresent(String.self, forKey: .endTimeZone)
        allDay = (try? c.decodeIfPresent(Bool.self, forKey: .allDay)) ?? false
        locationName = (try? c.decodeIfPresent(String.self, forKey: .locationName)) ?? ""
        address = (try? c.decodeIfPresent(String.self, forKey: .address)) ?? ""
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        confirmationCode = (try? c.decodeIfPresent(String.self, forKey: .confirmationCode)) ?? ""
        details = (try? c.decodeIfPresent([String: String].self, forKey: .details)) ?? [:]
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        reminderMinutes = try? c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
    }
}

struct ImportRequest: Encodable, Sendable {
    var text: String
}

struct ImportResponseDTO: Decodable, Sendable {
    var items: [ItemDraftDTO]
}

// MARK: - Member

struct MemberDTO: Codable, Equatable, Sendable {
    var tripId: String
    var userId: String
    var displayName: String
    var role: String
    var updatedAt: Int
    var deletedAt: Int?

    init(tripId: String, userId: String, displayName: String, role: String, updatedAt: Int, deletedAt: Int?) {
        self.tripId = tripId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripId = try c.decode(String.self, forKey: .tripId).lowercased()
        userId = try c.decode(String.self, forKey: .userId).lowercased()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? MemberRole.viewer.rawValue
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        deletedAt = try c.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

// MARK: - Sync

struct SyncResponseDTO: Decodable, Sendable {
    var trips: [TripDTO]
    var items: [ItemDTO]
    var members: [MemberDTO]
    var cursor: Int

    init(trips: [TripDTO], items: [ItemDTO], members: [MemberDTO], cursor: Int) {
        self.trips = trips
        self.items = items
        self.members = members
        self.cursor = cursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trips = try c.decodeIfPresent([TripDTO].self, forKey: .trips) ?? []
        items = try c.decodeIfPresent([ItemDTO].self, forKey: .items) ?? []
        members = try c.decodeIfPresent([MemberDTO].self, forKey: .members) ?? []
        cursor = try c.decode(Int.self, forKey: .cursor)
    }

    enum CodingKeys: String, CodingKey { case trips, items, members, cursor }
}

// MARK: - Devices

struct DeviceRegistrationDTO: Encodable, Equatable, Sendable {
    var apnsToken: String
    /// "sandbox" or "production".
    var environment: String
    var timeZone: String
    var briefingEnabled: Bool
    var briefingHour: Int
    var collabAlertsEnabled: Bool
}

struct OkDTO: Decodable, Sendable {
    var ok: Bool
}

// MARK: - Invites

struct CreateInviteRequest: Encodable, Sendable {
    /// "editor" or "viewer".
    var role: String
}

struct InviteDTO: Decodable, Equatable, Sendable {
    var code: String
    var url: String
    var expiresAt: Date
}

// MARK: - Errors

/// `{ "error": { "code": "string", "message": "human readable" } }`
struct APIErrorBody: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        var code: String
        var message: String
    }

    var error: Payload
}
