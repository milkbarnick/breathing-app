import Foundation

// Mapping between contract DTOs and SwiftData models. Every server row is applied as an
// idempotent upsert keyed by the lowercased id, so a repeated row from /v1/sync is harmless.

extension Trip {
    convenience init(dto: TripDTO) {
        self.init(
            id: dto.id,
            ownerId: dto.ownerId,
            title: dto.title,
            destination: dto.destination,
            startDate: dto.startDate,
            endDate: dto.endDate,
            timeZone: dto.timeZone,
            coverEmoji: dto.coverEmoji,
            colorHex: dto.colorHex,
            notes: dto.notes,
            updatedAt: dto.updatedAt
        )
    }

    /// Overwrites the synced fields with the server's version.
    func apply(_ dto: TripDTO) {
        ownerId = dto.ownerId.lowercased()
        title = dto.title
        destination = dto.destination
        startDate = dto.startDate
        endDate = dto.endDate
        timeZone = dto.timeZone
        coverEmoji = dto.coverEmoji
        colorHex = dto.colorHex
        notes = dto.notes
        updatedAt = dto.updatedAt
    }

    var writeDTO: TripWriteDTO {
        TripWriteDTO(
            title: title,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            timeZone: timeZone,
            coverEmoji: coverEmoji,
            colorHex: colorHex,
            notes: notes
        )
    }
}

extension Item {
    convenience init(dto: ItemDTO) {
        self.init(
            id: dto.id,
            tripId: dto.tripId,
            kind: ItemKind(rawValue: dto.kind) ?? .note,
            title: dto.title,
            startAt: dto.startAt,
            endAt: dto.endAt,
            startTimeZone: dto.startTimeZone,
            endTimeZone: dto.endTimeZone,
            allDay: dto.allDay,
            locationName: dto.locationName,
            address: dto.address,
            latitude: dto.latitude,
            longitude: dto.longitude,
            confirmationCode: dto.confirmationCode,
            details: dto.details,
            notes: dto.notes,
            reminderMinutes: dto.reminderMinutes,
            sortIndex: dto.sortIndex,
            updatedBy: dto.updatedBy,
            updatedAt: dto.updatedAt
        )
    }

    func apply(_ dto: ItemDTO) {
        tripId = dto.tripId.lowercased()
        kindRaw = (ItemKind(rawValue: dto.kind) ?? .note).rawValue
        title = dto.title
        startAt = dto.startAt
        endAt = dto.endAt
        startTimeZone = dto.startTimeZone
        endTimeZone = dto.endTimeZone
        allDay = dto.allDay
        locationName = dto.locationName
        address = dto.address
        latitude = dto.latitude
        longitude = dto.longitude
        confirmationCode = dto.confirmationCode
        details = dto.details
        notes = dto.notes
        reminderMinutes = dto.reminderMinutes
        sortIndex = dto.sortIndex
        updatedBy = dto.updatedBy
        updatedAt = dto.updatedAt
    }

    var writeDTO: ItemWriteDTO {
        ItemWriteDTO(
            id: id.lowercased(),
            tripId: tripId.lowercased(),
            kind: kindRaw,
            title: title,
            startAt: startAt.wholeSeconds,
            endAt: endAt?.wholeSeconds,
            startTimeZone: startTimeZone,
            endTimeZone: endTimeZone,
            allDay: allDay,
            locationName: locationName,
            address: address,
            latitude: latitude,
            longitude: longitude,
            confirmationCode: confirmationCode,
            details: details.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            notes: notes,
            reminderMinutes: reminderMinutes,
            sortIndex: sortIndex
        )
    }
}

extension Member {
    convenience init(dto: MemberDTO) {
        self.init(
            tripId: dto.tripId,
            userId: dto.userId,
            displayName: dto.displayName,
            role: MemberRole(rawValue: dto.role) ?? .viewer,
            updatedAt: dto.updatedAt
        )
    }

    func apply(_ dto: MemberDTO) {
        displayName = dto.displayName
        roleRaw = (MemberRole(rawValue: dto.role) ?? .viewer).rawValue
        updatedAt = dto.updatedAt
    }
}

extension Date {
    /// Drops fractional seconds, so a value survives the contract's second-precision round trip.
    var wholeSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
