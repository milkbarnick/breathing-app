import SwiftData
import SwiftUI

/// Root screen: Now / Upcoming / Past (UX spec 3.1).
struct TripsListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(TripStore.self) private var store
    @Environment(NetworkMonitor.self) private var network

    @Query(filter: #Predicate<Trip> { $0.pendingDelete == false }, sort: \Trip.startDate)
    private var trips: [Trip]
    @Query(filter: #Predicate<Item> { $0.pendingDelete == false })
    private var items: [Item]
    @Query private var members: [Member]

    @State private var searchText = ""
    @AppStorage("tripsList.pastExpanded") private var pastExpanded = false
    @State private var confirmingTrip: Trip?
    @State private var editingTrip: Trip?
    @State private var sharingTrip: Trip?
    @State private var firstSyncTimedOut = false

    var body: some View {
        let now = Date()
        let groups = TripGroups(trips: filteredTrips, now: now)

        List {
            if showsPlaceholders {
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        PlaceholderTripRow()
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !groups.now.isEmpty {
                Section("Now") {
                    ForEach(groups.now) { trip in
                        tripButton(trip) {
                            HeroTripCard(trip: trip, items: itemsByTrip[trip.id] ?? [], now: now)
                        }
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l))
                        .listRowBackground(Color.clear)
                    }
                }
            }

            if !groups.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(groups.upcoming) { trip in
                        tripButton(trip) { row(for: trip, now: now) }
                            .listRowBackground(Palette.surface)
                    }
                }
            }

            if !groups.past.isEmpty {
                Section("Past") {
                    if groups.past.count > 3 && !pastExpanded && searchText.isEmpty {
                        Button {
                            pastExpanded = true
                        } label: {
                            Label("Show \(groups.past.count) past trips", systemImage: "chevron.down")
                        }
                        .listRowBackground(Palette.surface)
                    } else {
                        ForEach(groups.past) { trip in
                            tripButton(trip) { row(for: trip, now: now) }
                                .listRowBackground(Palette.surface)
                        }
                        if groups.past.count > 3 && searchText.isEmpty {
                            Button("Show fewer") { pastExpanded = false }
                                .listRowBackground(Palette.surface)
                        }
                    }
                }
            }

            statusSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Trips")
        .toolbar { toolbarContent }
        .modifier(SearchableIfNeeded(enabled: trips.count >= 6, text: $searchText))
        .refreshable { await sync.syncNow() }
        .overlay { emptyState }
        .offlineBanner(network)
        .confirmationDialog(confirmTitle, isPresented: isConfirming, titleVisibility: .visible,
                            presenting: confirmingTrip) { trip in
            Button(isOwner(trip) ? "Delete Trip" : "Leave Trip", role: .destructive) {
                store.deleteOrLeave(trip)
            }
        } message: { trip in
            Text(confirmMessage(trip))
        }
        .sensoryFeedback(.warning, trigger: confirmingTrip != nil) { _, new in new }
        .sheet(item: $editingTrip) { trip in
            TripEditorView(trip: trip)
        }
        .sheet(item: $sharingTrip) { trip in
            ShareTripView(tripId: trip.id)
        }
        .task(id: sync.isSyncing) {
            guard trips.isEmpty, sync.hasNeverSynced, sync.isSyncing else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            firstSyncTimedOut = true
        }
    }

    // MARK: - Rows

    private func tripButton<Content: View>(_ trip: Trip, @ViewBuilder content: () -> Content) -> some View {
        let role = store.role(for: trip)
        return Button {
            router.path = [.trip(trip.id)]
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                confirmingTrip = trip
            } label: {
                if role == .owner {
                    Label("Delete", systemImage: "trash")
                } else {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .contextMenu {
            Button {
                router.path = [.trip(trip.id)]
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            if role.canEdit {
                Button {
                    editingTrip = trip
                } label: {
                    Label("Edit Trip", systemImage: "pencil")
                }
                Button {
                    sharingTrip = trip
                } label: {
                    Label("Share", systemImage: "person.2.fill")
                }
            }
            Divider()
            Button(role: .destructive) {
                confirmingTrip = trip
            } label: {
                if role == .owner {
                    Label("Delete Trip", systemImage: "trash")
                } else {
                    Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .accessibilityAction(named: "Edit") {
            if role.canEdit { editingTrip = trip }
        }
    }

    private func row(for trip: Trip, now: Date) -> some View {
        TripRow(trip: trip, role: store.role(for: trip), isShared: memberCount(trip.id) > 1, now: now)
    }

    // MARK: - Sections and states

    @ViewBuilder
    private var statusSection: some View {
        if !trips.isEmpty || firstSyncTimedOut {
            Section {
                EmptyView()
            } footer: {
                HStack(spacing: Spacing.xs) {
                    if sync.lastErrorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                        Text("Couldn't sync. Pull to retry.")
                    } else if !network.isOnline || sync.lastFailureWasOffline {
                        Image(systemName: "wifi.slash")
                        Text("Offline, changes saved")
                    } else if firstSyncTimedOut && trips.isEmpty {
                        Text("Still syncing…")
                    } else {
                        Text("Synced \(TimeFormat.lastSynced(sync.lastSyncedAt))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if trips.isEmpty && !showsPlaceholders {
            ContentUnavailableView {
                Label {
                    Text("No trips yet")
                } icon: {
                    Image(systemName: "suitcase.rolling.fill")
                        .foregroundStyle(Palette.accent)
                }
            } description: {
                Text("Create a trip, then add flights, stays and plans, or paste a confirmation email and let Wayfare fill it in.")
            } actions: {
                Button("New Trip") { router.sheet = .newTrip }
                    .buttonStyle(.borderedProminent)
                Button("Join with Code") { router.sheet = .joinWithCode(prefill: nil) }
                    .buttonStyle(.bordered)
            }
        } else if !searchText.isEmpty && filteredTrips.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router.sheet = .settings
            } label: {
                AvatarCircle(name: session.displayName.isEmpty ? "?" : session.displayName,
                             color: Palette.accent, size: 32)
            }
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    router.sheet = .newTrip
                } label: {
                    Label("New Trip", systemImage: "plus")
                }
                Button {
                    router.sheet = .joinWithCode(prefill: nil)
                } label: {
                    Label("Join with Code", systemImage: "link")
                }
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("Add")
            }
        }
    }

    // MARK: - Data

    private var showsPlaceholders: Bool {
        trips.isEmpty && sync.hasNeverSynced && sync.isSyncing && !firstSyncTimedOut
    }

    private var itemsByTrip: [String: [ItemSnapshot]] {
        Dictionary(grouping: items.map(\.snapshot), by: \.tripId)
    }

    private func memberCount(_ tripId: String) -> Int {
        members.filter { $0.tripId == tripId }.count
    }

    private var filteredTrips: [Trip] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return trips }
        let matchingTripIds = Set(items.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.locationName.localizedCaseInsensitiveContains(query)
        }.map(\.tripId))
        return trips.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.destination.localizedCaseInsensitiveContains(query)
                || matchingTripIds.contains($0.id)
        }
    }

    private func isOwner(_ trip: Trip) -> Bool {
        store.role(for: trip) == .owner
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirmingTrip != nil }, set: { if !$0 { confirmingTrip = nil } })
    }

    private var confirmTitle: String {
        guard let trip = confirmingTrip else { return "" }
        return isOwner(trip) ? "Delete “\(trip.displayTitle)”?" : "Leave “\(trip.displayTitle)”?"
    }

    private func confirmMessage(_ trip: Trip) -> String {
        if isOwner(trip) {
            let count = itemsByTrip[trip.id]?.count ?? 0
            return "This deletes the trip and all \(count) plans for everyone it's shared with. This can't be undone."
        }
        return "You'll lose access until someone invites you again."
    }
}

/// Splits trips into Now / Upcoming / Past using today's date in each trip's zone.
struct TripGroups {
    var now: [Trip] = []
    var upcoming: [Trip] = []
    var past: [Trip] = []

    init(trips: [Trip], now date: Date) {
        for trip in trips {
            switch trip.phase(now: date) {
            case .inProgress: now.append(trip)
            case .upcoming: upcoming.append(trip)
            case .past: past.append(trip)
            }
        }
        upcoming.sort { $0.startDay < $1.startDay }
        past.sort { $0.endDay > $1.endDay }
    }
}

/// `.searchable` only once there are 6 or more trips.
struct SearchableIfNeeded: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .automatic),
                               prompt: "Search trips and plans")
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        TripsListView()
    }
    .previewServices()
}
