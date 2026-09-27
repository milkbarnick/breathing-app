import SwiftData
import SwiftUI

enum TripSegment: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case map = "Map"
    case info = "Info"

    var id: String { rawValue }
}

/// Remembers the selected segment per trip for the session (UX spec 1.2).
@MainActor
enum SegmentMemory {
    static var byTrip: [String: TripSegment] = [:]
}

/// Opens the Add Item sheet with an optional kind and a preset day.
struct AddItemRequest: Identifiable {
    let id = UUID()
    let kind: ItemKind?
    let day: CalendarDay
}

/// Trip Detail container: header, Timeline | Map | Info (UX spec 3.3).
struct TripDetailView: View {
    let tripId: String

    @Environment(AppRouter.self) private var router
    @Environment(TripStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(NetworkMonitor.self) private var network

    @Query private var trips: [Trip]
    @Query private var itemRows: [Item]
    @Query private var members: [Member]

    @State private var segment: TripSegment = .timeline
    @State private var kindFilter: ItemKind?
    @State private var addRequest: AddItemRequest?
    @State private var editingItem: Item?
    @State private var showingImport = false
    @State private var showingShare = false
    @State private var showingEditTrip = false
    @State private var showingViewerInfo = false
    @State private var lastKnownTitle: String?

    init(tripId: String) {
        let id = tripId.lowercased()
        self.tripId = id
        _trips = Query(filter: #Predicate<Trip> { $0.id == id })
        _itemRows = Query(filter: #Predicate<Item> { $0.tripId == id && $0.pendingDelete == false },
                          sort: [SortDescriptor(\Item.startAt)])
        _members = Query(filter: #Predicate<Member> { $0.tripId == id })
    }

    private var trip: Trip? {
        guard let trip = trips.first, !trip.pendingDelete else { return nil }
        return trip
    }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                ContentUnavailableView("Trip unavailable", systemImage: "suitcase.rolling",
                                       description: Text("This trip is no longer available."))
            }
        }
        .background(Palette.background)
        .onAppear {
            lastKnownTitle = trip?.displayTitle
            segment = SegmentMemory.byTrip[tripId] ?? .timeline
        }
        .onChange(of: trip == nil) { _, isGone in
            // Deleted, or we were removed from it, while open (UX spec 5.6).
            if isGone, let title = lastKnownTitle {
                toasts.show("\(title) is no longer available.", systemImage: "exclamationmark.triangle.fill")
                router.popToRoot()
            }
        }
        .onChange(of: segment) { _, newValue in
            SegmentMemory.byTrip[tripId] = newValue
        }
    }

    private func content(_ trip: Trip) -> some View {
        let role = store.role(for: trip)
        let snapshots = itemRows.map(\.snapshot)
        return VStack(spacing: 0) {
            header(trip, role: role)
            Picker("View", selection: $segment) {
                ForEach(TripSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
            .sensoryFeedback(.selection, trigger: segment)

            switch segment {
            case .timeline:
                TripTimelineView(
                    trip: trip, items: snapshots, canEdit: role.canEdit, isShared: members.count > 1,
                    kindFilter: kindFilter,
                    onClearFilter: { kindFilter = nil },
                    onAdd: { kind, day in addRequest = AddItemRequest(kind: kind, day: day) },
                    onImport: { showingImport = true },
                    onEdit: { id in editingItem = itemRows.first { $0.id == id } },
                    onDelete: { id in
                        if let item = itemRows.first(where: { $0.id == id }) { store.deleteItem(item) }
                    },
                    onDuplicate: { id in
                        if let item = itemRows.first(where: { $0.id == id }) {
                            store.duplicateItem(item)
                            toasts.show("Duplicated")
                        }
                    }
                )
                .transition(.opacity)
            case .map:
                DayMapView(trip: trip, items: snapshots)
                    .transition(.opacity)
            case .info:
                TripInfoView(trip: trip, items: snapshots, members: members, role: role,
                             onEditTrip: { showingEditTrip = true },
                             onShare: { showingShare = true },
                             onFilter: { kind in
                                 kindFilter = kind
                                 segment = .timeline
                             })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: segment)
        .offlineBanner(network)
        .navigationTitle("\(trip.coverEmoji) \(trip.displayTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(trip, role: role) }
        .sheet(item: $addRequest) { request in
            ItemEditorView(trip: trip, mode: .new(kind: request.kind, day: request.day))
        }
        .sheet(item: $editingItem) { item in
            ItemEditorView(trip: trip, mode: .edit(item))
        }
        .sheet(isPresented: $showingImport) {
            ImportView(trip: trip)
        }
        .sheet(isPresented: $showingShare) {
            ShareTripView(tripId: trip.id)
        }
        .sheet(isPresented: $showingEditTrip) {
            TripEditorView(trip: trip)
        }
    }

    private func header(_ trip: Trip, role: MemberRole) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(TimeFormat.longDateRange(trip.startDay, trip.endDay))
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                if case .inProgress(let day, let total) = trip.phase() {
                    Text("Day \(day) of \(total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.accent)
                }
                if router.updatingTripId == trip.id {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Updating…")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if role == .viewer {
                Button {
                    showingViewerInfo = true
                } label: {
                    Pill(text: "View only", style: .viewOnly, systemImage: "eye")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingViewerInfo) {
                    Text("\(ownerName(trip)) shared this trip with you as a viewer. Ask them for edit access.")
                        .font(.subheadline)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    @ToolbarContentBuilder
    private func toolbar(_ trip: Trip, role: MemberRole) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingShare = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill")
                    if members.count > 1 {
                        Text("\(members.count)")
                            .font(.footnote.monospacedDigit())
                    }
                }
            }
            .accessibilityLabel(members.count > 1 ? "Share, \(members.count) people" : "Share")

            if role.canEdit {
                Menu {
                    ForEach(ItemKind.allCases) { kind in
                        Button {
                            addRequest = AddItemRequest(kind: kind, day: defaultDay(trip))
                        } label: {
                            Label(kind.displayName, systemImage: kind.symbol)
                        }
                    }
                    Divider()
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import from Email…", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add")
                }
            }
        }
    }

    /// Today when the trip is in progress, otherwise its first day.
    private func defaultDay(_ trip: Trip) -> CalendarDay {
        trip.phase().isInProgress ? CalendarDay.today(in: trip.tz) : trip.startDay
    }

    private func ownerName(_ trip: Trip) -> String {
        members.first { $0.userId == trip.ownerId }?.nameForDisplay ?? "The owner"
    }
}

#Preview {
    NavigationStack {
        TripDetailView(tripId: SampleData.tripId)
    }
    .previewServices()
}
