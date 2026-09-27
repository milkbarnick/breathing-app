import Foundation
import SwiftData

/// Offline-first sync (decision D6).
///
/// 1. Push dirty rows: trip upserts, then item upserts/deletes, then trip deletes/leaves.
/// 2. Pull `GET /v1/sync?since=<cursor>` and apply every row as an idempotent upsert keyed by the
///    lowercased id. Tombstones (`deletedAt` set) delete the local row.
/// 3. Store the new cursor and reschedule local reminders.
///
/// Runs on launch, on foreground, after local edits (debounced), on pull-to-refresh, on reconnect,
/// and when an `itemChanged` push arrives. Everything is async on the main actor; nothing blocks the UI,
/// and all local reads and writes keep working offline.
@MainActor
@Observable
final class SyncEngine {
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    /// A user-facing message for the last failed sync that wasn't just "offline".
    private(set) var lastErrorMessage: String?
    /// True when the last sync failed because there was no connection.
    private(set) var lastFailureWasOffline = false
    /// Number of local rows waiting to be pushed.
    private(set) var pendingChangeCount = 0
    /// One-time notice when the server rejected local changes (e.g. role downgraded to viewer).
    var discardNotice: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let scheduler: NotificationScheduler
    @ObservationIgnored private let defaults: UserDefaults
    /// The signed-in user's id, for "leave trip" and ownership checks.
    @ObservationIgnored var currentUserId: () -> String? = { nil }

    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var needsFullResync = false
    @ObservationIgnored private var discardedCount = 0

    static let cursorKey = "sync.cursor"
    static let lastSyncedKey = "sync.lastSyncedAt"

    init(context: ModelContext, api: APIClient, scheduler: NotificationScheduler, defaults: UserDefaults = .standard) {
        self.context = context
        self.api = api
        self.scheduler = scheduler
        self.defaults = defaults
        let stamp = defaults.double(forKey: Self.lastSyncedKey)
        lastSyncedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        refreshPendingCount()
    }

    /// The last server cursor (ms). 0 means "everything".
    var cursor: Int {
        get { defaults.integer(forKey: Self.cursorKey) }
        set { defaults.set(newValue, forKey: Self.cursorKey) }
    }

    /// True before the first successful sync on this install.
    var hasNeverSynced: Bool { lastSyncedAt == nil }

    // MARK: - Triggers

    /// Fire-and-forget sync (launch, foreground, reconnect, push).
    func requestSync() {
        Task { await syncNow() }
    }

    /// Call after every local edit. Waits 1.5 s so a burst of edits becomes one sync.
    func localChangeMade() {
        refreshPendingCount()
        scheduler.reschedule()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs a sync, or joins the one in flight (and asks it to run once more). Safe to await from
    /// `.refreshable`.
    func syncNow() async {
        if let runningTask {
            rerunRequested = true
            await runningTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested = false
                await self.performSync()
            } while self.rerunRequested && !Task.isCancelled
            self.runningTask = nil
        }
        runningTask = task
        await task.value
    }

    /// Sign-out / account deletion: stop work and forget the cursor.
    func reset() {
        debounceTask?.cancel()
        runningTask?.cancel()
        runningTask = nil
        rerunRequested = false
        needsFullResync = false
        cursor = 0
        defaults.removeObject(forKey: Self.lastSyncedKey)
        lastSyncedAt = nil
        lastErrorMessage = nil
        lastFailureWasOffline = false
        pendingChangeCount = 0
        discardNotice = nil
    }

    func refreshPendingCount() {
        let trips = (try? context.fetchCount(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.needsPush == true || $0.pendingDelete == true }))) ?? 0
        let items = (try? context.fetchCount(FetchDescriptor<Item>(
            predicate: #Predicate { $0.needsPush == true || $0.pendingDelete == true }))) ?? 0
        pendingChangeCount = trips + items
    }

    // MARK: - One pass

    private func performSync() async {
        guard api.hasToken else { return }
        isSyncing = true
        discardedCount = 0
        do {
            try await pushTripUpserts()
            try await pushItems()
            try await pushTripDeletes()
            try await pull()
            lastSyncedAt = Date()
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastSyncedKey)
            lastErrorMessage = nil
            lastFailureWasOffline = false
        } catch let error as APIError {
            saveQuietly()
            switch error {
            case .cancelled:
                break
            case .offline, .timedOut:
                lastFailureWasOffline = true
            case .notSignedIn:
                break
            default:
                lastFailureWasOffline = false
                lastErrorMessage = error.isUnauthorized ? "Please sign in again." : "Couldn't sync. Pull to retry."
            }
        } catch is CancellationError {
            // Signed out mid-sync; nothing to report.
        } catch {
            saveQuietly()
            lastErrorMessage = "Couldn't sync. Pull to retry."
        }
        if discardedCount > 0 {
            discardNotice = discardedCount == 1
                ? "1 unsynced change was discarded because you can no longer edit that trip."
                : "\(discardedCount) unsynced changes were discarded because you can no longer edit those trips."
        }
        isSyncing = false
        refreshPendingCount()
        scheduler.reschedule()
    }

    // MARK: - Push

    private func pushTripUpserts() async throws {
        let dirty = try context.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.needsPush == true && $0.pendingDelete == false }))
        for trip in dirty {
            let revision = trip.localRevision
            let tripId = trip.id.lowercased()
            do {
                let dto = try await api.putTrip(id: tripId, trip.writeDTO)
                try Task.checkCancellation()
                if trip.localRevision == revision {
                    trip.apply(dto)
                    trip.needsPush = false
                } else {
                    // Edited again while the request was in flight: keep the newer local copy dirty.
                    trip.updatedAt = dto.updatedAt
                    trip.ownerId = dto.ownerId
                }
            } catch let error as APIError where error.isPermanentRejection {
                try Task.checkCancellation()
                rejectTrip(trip)
            }
        }
        try context.save()
    }

    private func pushItems() async throws {
        let deletingTripIds = Set(try context.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.pendingDelete == true })).map { $0.id.lowercased() })
        let dirty = try context.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.needsPush == true || $0.pendingDelete == true }))

        for item in dirty {
            let tripId = item.tripId.lowercased()
            let itemId = item.id.lowercased()
            if deletingTripIds.contains(tripId) {
                continue // The trip delete/leave takes these with it.
            }
            if item.pendingDelete {
                if item.updatedAt == 0 {
                    context.delete(item) // Never reached the server.
                    continue
                }
                do {
                    try await api.deleteItem(tripId: tripId, itemId: itemId)
                    try Task.checkCancellation()
                    context.delete(item)
                } catch let error as APIError where error.isNotFound {
                    try Task.checkCancellation()
                    context.delete(item)
                } catch let error as APIError where error.isPermanentRejection {
                    try Task.checkCancellation()
                    item.pendingDelete = false
                    item.needsPush = false
                    needsFullResync = true
                    discardedCount += 1
                }
            } else {
                let revision = item.localRevision
                do {
                    let dto = try await api.putItem(item.writeDTO)
                    try Task.checkCancellation()
                    if item.localRevision == revision {
                        item.apply(dto)
                        item.needsPush = false
                    } else {
                        item.updatedAt = dto.updatedAt
                        item.updatedBy = dto.updatedBy
                    }
                } catch let error as APIError where error.isPermanentRejection {
                    try Task.checkCancellation()
                    rejectItem(item)
                }
            }
        }
        try context.save()
    }

    private func pushTripDeletes() async throws {
        let deleting = try context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.pendingDelete == true }))
        let me = currentUserId()?.lowercased()
        for trip in deleting {
            let tripId = trip.id.lowercased()
            if trip.updatedAt == 0 {
                deleteTripLocally(tripId)
                continue
            }
            do {
                if trip.ownerId.lowercased() == me || me == nil {
                    try await api.deleteTrip(id: tripId)
                } else if let me {
                    try await api.removeMember(tripId: tripId, userId: me)
                }
                try Task.checkCancellation()
                deleteTripLocally(tripId)
            } catch let error as APIError where error.isNotFound {
                try Task.checkCancellation()
                deleteTripLocally(tripId)
            } catch let error as APIError where error.isPermanentRejection {
                try Task.checkCancellation()
                trip.pendingDelete = false
                needsFullResync = true
                discardedCount += 1
            }
        }
        try context.save()
    }

    /// The server refused a trip write. A row it never had is dropped; otherwise we re-pull its version.
    private func rejectTrip(_ trip: Trip) {
        discardedCount += 1
        if trip.updatedAt == 0 {
            deleteTripLocally(trip.id.lowercased())
        } else {
            trip.needsPush = false
            needsFullResync = true
        }
    }

    private func rejectItem(_ item: Item) {
        discardedCount += 1
        if item.updatedAt == 0 {
            context.delete(item)
        } else {
            item.needsPush = false
            needsFullResync = true
        }
    }

    // MARK: - Pull

    private func pull() async throws {
        let since = needsFullResync ? 0 : cursor
        let response = try await api.sync(since: since)
        try Task.checkCancellation()
        try apply(response)
        cursor = response.cursor
        needsFullResync = false
    }

    /// Applies one `/v1/sync` response. Rows may repeat (the server's cursor overlaps by a few seconds,
    /// and newly joined trips come back in full), so every row is an idempotent upsert by lowercased id.
    /// Rows with unpushed local changes are skipped: our write will be sent next and wins (LWW).
    func apply(_ response: SyncResponseDTO) throws {
        // Rows for trips tombstoned in this same response are dropped with the trip.
        let deadTripIds = Set(response.trips.filter { $0.deletedAt != nil }.map { $0.id.lowercased() })

        // Trips
        var trips = try Self.index(context.fetch(FetchDescriptor<Trip>())) { $0.id.lowercased() }
        for dto in response.trips {
            let id = dto.id.lowercased()
            if dto.deletedAt != nil {
                deleteTripLocally(id)
                trips[id] = nil
                continue
            }
            if let trip = trips[id] {
                if trip.needsPush || trip.pendingDelete { continue }
                trip.apply(dto)
            } else {
                let trip = Trip(dto: dto)
                context.insert(trip)
                trips[id] = trip
            }
        }

        // Commit trip deletions before indexing items, so deleted rows can't be matched again.
        try context.save()

        // Items
        var items = try Self.index(context.fetch(FetchDescriptor<Item>())) { $0.id.lowercased() }
        for dto in response.items {
            let id = dto.id.lowercased()
            if deadTripIds.contains(dto.tripId.lowercased()) { continue }
            if dto.deletedAt != nil {
                if let item = items[id], !item.needsPush {
                    context.delete(item)
                    items[id] = nil
                }
                continue
            }
            if let item = items[id] {
                if item.needsPush || item.pendingDelete { continue }
                item.apply(dto)
            } else {
                let item = Item(dto: dto)
                context.insert(item)
                items[id] = item
            }
        }

        // Members
        var members = try Self.index(context.fetch(FetchDescriptor<Member>())) { $0.key }
        for dto in response.members {
            let key = Member.key(tripId: dto.tripId, userId: dto.userId)
            if deadTripIds.contains(dto.tripId.lowercased()) { continue }
            if dto.deletedAt != nil {
                if let member = members[key] {
                    context.delete(member)
                    members[key] = nil
                }
                continue
            }
            if let member = members[key] {
                member.apply(dto)
            } else {
                let member = Member(dto: dto)
                context.insert(member)
                members[key] = member
            }
        }

        try context.save()
    }

    /// Deletes a trip with its items and members (tombstone, removal, confirmed delete/leave).
    func deleteTripLocally(_ tripId: String) {
        let id = tripId.lowercased()
        if let trips = try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })) {
            trips.forEach { context.delete($0) }
        }
        if let items = try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.tripId == id })) {
            items.forEach { context.delete($0) }
        }
        if let members = try? context.fetch(FetchDescriptor<Member>(predicate: #Predicate { $0.tripId == id })) {
            members.forEach { context.delete($0) }
        }
    }

    private func saveQuietly() {
        try? context.save()
    }

    /// Builds a dictionary, keeping the first row if ids ever collide.
    private static func index<T>(_ rows: [T], key: (T) -> String) -> [String: T] {
        var result: [String: T] = [:]
        for row in rows where result[key(row)] == nil {
            result[key(row)] = row
        }
        return result
    }
}
