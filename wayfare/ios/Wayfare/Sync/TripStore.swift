import Foundation
import SwiftData

/// Every local write goes through here: it writes SwiftData immediately (works offline), marks the row
/// dirty, reschedules reminders, and asks the sync engine for a debounced sync.
@MainActor
@Observable
final class TripStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let sync: SyncEngine
    @ObservationIgnored var currentUserId: () -> String? = { nil }

    init(context: ModelContext, sync: SyncEngine) {
        self.context = context
        self.sync = sync
    }

    // MARK: - Reads

    func trip(id: String) -> Trip? {
        let id = id.lowercased()
        return try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first
    }

    func item(id: String) -> Item? {
        let id = id.lowercased()
        return try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })).first
    }

    func tripExists(_ id: String) -> Bool {
        guard let trip = trip(id: id) else { return false }
        return !trip.pendingDelete
    }

    func itemExists(_ id: String) -> Bool {
        guard let item = item(id: id) else { return false }
        return !item.pendingDelete
    }

    func liveItems(tripId: String) -> [Item] {
        let id = tripId.lowercased()
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.tripId == id && $0.pendingDelete == false },
            sortBy: [SortDescriptor(\Item.startAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Items of live trips, for reminder scheduling.
    func liveItemSnapshots() -> [ItemSnapshot] {
        let deletingTrips = Set(((try? context.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.pendingDelete == true }))) ?? []).map(\.id))
        let items = (try? context.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.pendingDelete == false }))) ?? []
        return items.filter { !deletingTrips.contains($0.tripId) }.map(\.snapshot)
    }

    func members(tripId: String) -> [Member] {
        let id = tripId.lowercased()
        return (try? context.fetch(FetchDescriptor<Member>(predicate: #Predicate { $0.tripId == id }))) ?? []
    }

    /// The current user's role. A trip created on this device (no owner yet) is ours.
    func role(for trip: Trip) -> MemberRole {
        let me = currentUserId()?.lowercased()
        if trip.ownerId.isEmpty || trip.ownerId.lowercased() == me {
            return .owner
        }
        if let me, let member = members(tripId: trip.id).first(where: { $0.userId == me }) {
            return member.role
        }
        return .viewer
    }

    var tripCount: Int {
        (try? context.fetchCount(FetchDescriptor<Trip>(predicate: #Predicate { $0.pendingDelete == false }))) ?? 0
    }

    // MARK: - Trips

    @discardableResult
    func createTrip(from form: TripFormState) -> Trip {
        let trip = Trip(ownerId: currentUserId() ?? "", startDate: form.startDay.string, endDate: form.endDay.string)
        form.apply(to: trip)
        trip.markEdited()
        context.insert(trip)
        save()
        return trip
    }

    func updateTrip(_ trip: Trip, from form: TripFormState) {
        form.apply(to: trip)
        trip.markEdited()
        save()
    }

    /// Owner: delete for everyone. Others: leave. Hidden immediately; confirmed by the next sync.
    func deleteOrLeave(_ trip: Trip) {
        if trip.updatedAt == 0 {
            sync.deleteTripLocally(trip.id)
        } else {
            trip.pendingDelete = true
        }
        save()
    }

    /// Moves the trip's start or end so `day` is inside it (Item form "Extend Trip").
    func extendTrip(_ trip: Trip, toInclude day: CalendarDay) {
        if day < trip.startDay {
            trip.startDate = day.string
        } else if day > trip.endDay {
            trip.endDate = day.string
        } else {
            return
        }
        trip.markEdited()
        save()
    }

    /// Stores a trip returned by `POST /v1/invites/:code/accept`.
    func upsertAcceptedTrip(_ dto: TripDTO) {
        if let existing = trip(id: dto.id) {
            if !existing.needsPush {
                existing.apply(dto)
            }
            existing.pendingDelete = false
        } else {
            context.insert(Trip(dto: dto))
        }
        try? context.save()
    }

    func updateTripNotes(_ trip: Trip, notes: String) {
        trip.notes = notes
        trip.markEdited()
        save()
    }

    // MARK: - Items

    @discardableResult
    func saveItem(_ form: ItemFormState, existing: Item?, tripId: String) -> Item {
        if let existing {
            form.apply(to: existing)
            existing.markEdited()
            save()
            return existing
        }
        let item = form.makeItem(tripId: tripId)
        item.sortIndex = nextSortIndex(tripId: tripId, for: form)
        item.markEdited()
        context.insert(item)
        save()
        return item
    }

    /// Saves reviewed AI drafts as normal items with new ids.
    @discardableResult
    func addDrafts(_ forms: [ItemFormState], tripId: String) -> [Item] {
        var created: [Item] = []
        for form in forms {
            let item = form.makeItem(tripId: tripId)
            item.sortIndex = nextSortIndex(tripId: tripId, for: form) + created.count
            item.markEdited()
            context.insert(item)
            created.append(item)
        }
        save()
        return created
    }

    func deleteItem(_ item: Item) {
        if item.updatedAt == 0 {
            context.delete(item)
        } else {
            item.pendingDelete = true
            item.markEdited()
        }
        save()
    }

    @discardableResult
    func duplicateItem(_ item: Item) -> Item {
        var form = ItemFormState(item: item)
        form.title = item.title + " (copy)"
        let copy = form.makeItem(tripId: item.tripId)
        copy.sortIndex = item.sortIndex + 1
        copy.markEdited()
        context.insert(copy)
        save()
        return copy
    }

    /// `sortIndex` = position among same-day all-day items (UX spec 3.3.1); timed items just append.
    private func nextSortIndex(tripId: String, for form: ItemFormState) -> Int {
        let items = liveItems(tripId: tripId)
        guard form.allDay else { return items.count }
        let zone = TimeZone.resolve(form.startTimeZone)
        let day = CalendarDay(date: form.startAt, in: zone)
        return items.filter { $0.allDay && CalendarDay(date: $0.startAt, in: TimeZone.resolve($0.startTimeZone)) == day }.count
    }

    // MARK: - Wipe

    /// Deletes every local row (sign-out, account deletion, switching servers).
    func wipeAll() {
        try? context.delete(model: Item.self)
        try? context.delete(model: Member.self)
        try? context.delete(model: Trip.self)
        try? context.save()
    }

    private func save() {
        try? context.save()
        sync.localChangeMade()
    }
}
