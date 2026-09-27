import Foundation

extension ItemKind {
    /// The suggested `details` keys for each kind (contract "Item" section).
    var detailKeys: [String] {
        switch self {
        case .flight: return ["airline", "flightNumber", "fromCode", "toCode", "terminal", "gate", "seat"]
        case .lodging: return ["phone", "checkInTime", "checkOutTime", "roomType"]
        case .transport: return ["mode", "operator", "fromName", "toName", "seat"]
        case .activity, .food: return ["phone", "website", "bookingUrl", "partySize"]
        case .note: return []
        }
    }

    static let allKnownDetailKeys: Set<String> = Set(ItemKind.allCases.flatMap(\.detailKeys))
}

/// Editable copy of an item for the Add / Edit Item form and for AI draft review.
struct ItemFormState: Equatable, Identifiable {
    /// Local identity for lists of drafts. Saved items get a fresh UUID in `makeItem`.
    var id = UUID()
    var kind: ItemKind
    var title: String = ""
    var startAt: Date
    var endAt: Date?
    var startTimeZone: String
    var endTimeZone: String?
    var allDay: Bool = false
    var locationName: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var confirmationCode: String = ""
    var details: [String: String] = [:]
    var notes: String = ""
    var reminderMinutes: Int?

    /// Set when the user picks a start zone by hand, so location search no longer overrides it.
    var startZoneChosenManually = false

    init(kind: ItemKind, startAt: Date, startTimeZone: String) {
        self.kind = kind
        self.startAt = startAt
        self.startTimeZone = startTimeZone
    }

    // MARK: Builders

    /// Defaults on Add (UX spec 3.5): the given day or the trip start, 09:00 in the trip zone;
    /// lodging 15:00 → next day 11:00; food 19:30; notes are all-day.
    static func new(kind: ItemKind, tripZone: String, day: CalendarDay) -> ItemFormState {
        let zone = TimeZone.resolve(tripZone)
        let time: (hour: Int, minute: Int)
        switch kind {
        case .lodging: time = (15, 0)
        case .food: time = (19, 30)
        default: time = (9, 0)
        }
        let start = day.date(hour: time.hour, minute: time.minute, in: zone) ?? Date()
        var form = ItemFormState(kind: kind, startAt: start, startTimeZone: zone.identifier)
        form.reminderMinutes = kind.defaultReminderMinutes
        if kind == .note {
            form.allDay = true
            form.startAt = day.startDate(in: zone) ?? start
        }
        if kind == .lodging {
            form.endAt = day.adding(days: 1).date(hour: 11, minute: 0, in: zone)
        }
        if kind == .transport {
            form.details["mode"] = TransportMode.train.rawValue
        }
        return form
    }

    init(item: Item) {
        self.init(snapshot: item.snapshot)
    }

    init(snapshot item: ItemSnapshot) {
        kind = item.kind
        title = item.title
        startAt = item.startAt
        endAt = item.endAt
        startTimeZone = item.startTimeZone
        endTimeZone = item.endTimeZone
        allDay = item.allDay
        locationName = item.locationName
        address = item.address
        latitude = item.latitude
        longitude = item.longitude
        confirmationCode = item.confirmationCode
        details = item.details
        notes = item.notes
        reminderMinutes = item.reminderMinutes
        startZoneChosenManually = true
    }

    /// A reviewable form from an AI draft. Missing or invalid zones fall back to the trip zone
    /// (the review screen flags it); a missing start falls back to the trip's first day at 09:00.
    init(draft: ItemDraftDTO, tripZone: String, fallbackDay: CalendarDay) {
        let kind = ItemKind(rawValue: draft.kind) ?? .note
        let zone = TimeZone(identifier: draft.startTimeZone ?? "") ?? TimeZone.resolve(tripZone)
        let start = draft.startAt ?? fallbackDay.date(hour: 9, minute: 0, in: zone) ?? Date()
        self.init(kind: kind, startAt: start, startTimeZone: zone.identifier)
        title = draft.title
        endAt = draft.endAt
        if let endZone = draft.endTimeZone, TimeZone(identifier: endZone) != nil {
            endTimeZone = endZone
        }
        allDay = draft.allDay
        locationName = draft.locationName
        address = draft.address
        latitude = draft.latitude
        longitude = draft.longitude
        confirmationCode = draft.confirmationCode
        details = draft.details
        notes = draft.notes
        reminderMinutes = draft.reminderMinutes ?? kind.defaultReminderMinutes
        startZoneChosenManually = true
    }

    // MARK: Zones

    var startZone: TimeZone { TimeZone.resolve(startTimeZone) }
    var endZone: TimeZone { TimeZone.resolve(endTimeZone ?? startTimeZone, fallback: startZone) }

    /// Only flight and transport have their own arrival zone row (UX spec 3.5).
    var hasOwnEndZone: Bool { kind == .flight || kind == .transport }

    var showsAllDayToggle: Bool { kind != .flight && kind != .transport }

    var endIsRequired: Bool { kind == .lodging }

    // MARK: Details

    func detail(_ key: String) -> String {
        details[key] ?? ""
    }

    mutating func setDetail(_ key: String, _ value: String) {
        details[key] = value
    }

    // MARK: Validation

    /// Flight auto-title: "{flightNumber} {fromCode} → {toCode}" when the title is empty.
    var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty || kind != .flight { return trimmed }
        let number = detail("flightNumber").trimmingCharacters(in: .whitespaces)
        let from = detail("fromCode").trimmingCharacters(in: .whitespaces)
        let to = detail("toCode").trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty || (!from.isEmpty && !to.isEmpty) else { return "" }
        var parts: [String] = []
        if !number.isEmpty { parts.append(number) }
        if !from.isEmpty && !to.isEmpty { parts.append("\(from) → \(to)") }
        return parts.joined(separator: " ")
    }

    /// Error text under the End row, or nil. End must be after start as an instant (not wall clock).
    var endError: String? {
        if endIsRequired && endAt == nil {
            return "Add a check-out time."
        }
        guard let endAt else { return nil }
        let start = normalizedStart
        let end = allDay ? (CalendarDay(date: endAt, in: endZone).startDate(in: endZone) ?? endAt) : endAt
        if allDay ? end < start : end <= start {
            switch kind {
            case .flight, .transport: return "Arrival must be after departure."
            case .lodging: return "Check-out must be after check-in."
            default: return "End must be after start."
            }
        }
        return nil
    }

    var isValid: Bool {
        !effectiveTitle.isEmpty && effectiveTitle.count <= 200 && endError == nil
    }

    /// All-day items are stored at local midnight in the start zone (UX spec 5.1).
    var normalizedStart: Date {
        guard allDay else { return startAt.wholeSeconds }
        return CalendarDay(date: startAt, in: startZone).startDate(in: startZone) ?? startAt
    }

    var normalizedEnd: Date? {
        guard let endAt else { return nil }
        guard allDay else { return endAt.wholeSeconds }
        return CalendarDay(date: endAt, in: endZone).startDate(in: endZone) ?? endAt
    }

    /// Details to store: trimmed, empty values dropped, and keys that belong only to other kinds removed
    /// (a kind change hides them while editing and deletes them on save). Unknown keys are kept.
    var cleanedDetails: [String: String] {
        let ownKeys = Set(kind.detailKeys)
        var result: [String: String] = [:]
        for (key, value) in details {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if ItemKind.allKnownDetailKeys.contains(key) && !ownKeys.contains(key) { continue }
            result[key] = trimmed
        }
        return result
    }

    // MARK: Output

    func apply(to item: Item) {
        item.kind = kind
        item.title = effectiveTitle
        item.startAt = normalizedStart
        item.endAt = normalizedEnd
        item.startTimeZone = startTimeZone
        item.endTimeZone = hasOwnEndZone ? endTimeZone : nil
        item.allDay = showsAllDayToggle ? allDay : false
        item.locationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        item.latitude = latitude
        item.longitude = longitude
        item.confirmationCode = kind == .note ? "" : confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = cleanedDetails
        item.notes = notes
        item.reminderMinutes = reminderMinutes
    }

    /// A new item with a fresh lowercase UUID.
    func makeItem(tripId: String) -> Item {
        let item = Item(tripId: tripId, kind: kind, title: effectiveTitle, startAt: normalizedStart,
                        startTimeZone: startTimeZone)
        apply(to: item)
        return item
    }

    /// A read-only snapshot for previews of drafts (review list, duplicate checks).
    func snapshot(tripId: String) -> ItemSnapshot {
        ItemSnapshot(
            id: id.uuidString.lowercased(), tripId: tripId, kind: kind, title: effectiveTitle,
            startAt: normalizedStart, endAt: normalizedEnd, startTimeZone: startTimeZone,
            endTimeZone: hasOwnEndZone ? endTimeZone : nil, allDay: allDay,
            locationName: locationName, address: address, latitude: latitude, longitude: longitude,
            confirmationCode: confirmationCode, details: cleanedDetails, notes: notes,
            reminderMinutes: reminderMinutes
        )
    }
}
