import MapKit
import SwiftData
import SwiftUI

/// Everything needed at the counter or the door (UX spec 3.4).
struct ItemDetailView: View {
    let itemId: String

    @Environment(AppRouter.self) private var router
    @Environment(TripStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(NotificationPermission.self) private var permission

    @Query private var matches: [Item]
    @Query private var members: [Member]

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var showingLargeCode = false
    @State private var copyCount = 0
    @State private var lastTitle: String?

    init(itemId: String) {
        let id = itemId.lowercased()
        self.itemId = id
        _matches = Query(filter: #Predicate<Item> { $0.id == id })
    }

    private var item: Item? {
        guard let item = matches.first, !item.pendingDelete else { return nil }
        return item
    }

    var body: some View {
        Group {
            if let item, let trip = store.trip(id: item.tripId) {
                content(item: item, trip: trip)
            } else {
                ContentUnavailableView("Plan unavailable", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("This plan was deleted."))
            }
        }
        .background(Palette.background)
        .onAppear { lastTitle = item?.title }
        .onChange(of: item == nil) { _, isGone in
            // Deleted by someone else while open (UX spec 5.6).
            guard isGone, let title = lastTitle else { return }
            toasts.show("“\(title)” was deleted.", systemImage: "trash")
            if case .item(let id)? = router.path.last, id == itemId {
                router.path.removeLast()
            }
        }
        .onChange(of: item?.title) { _, newTitle in
            if let newTitle { lastTitle = newTitle }
        }
    }

    private func content(item: Item, trip: Trip) -> some View {
        let snapshot = item.snapshot
        let canEdit = store.role(for: trip).canEdit
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ItemHeaderCard(item: snapshot, tripZone: trip.tz)
                actionRow(snapshot)
                if !snapshot.confirmationCode.isEmpty {
                    codeBlock(snapshot.confirmationCode)
                }
                if snapshot.hasCoordinates {
                    locationBlock(snapshot)
                } else if !snapshot.locationName.isEmpty || !snapshot.address.isEmpty {
                    addressBlock(snapshot)
                }
                detailsList(snapshot)
                if !snapshot.notes.isEmpty && snapshot.kind != .note {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Notes").font(.headline)
                        Text(snapshot.notes)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .wfCard()
                }
                reminderRow(snapshot)
                footer(snapshot)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
        }
        .navigationTitle(snapshot.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canEdit {
                    Button("Edit") { editing = true }
                }
                Menu {
                    Button {
                        SystemActions.copy(copyDetailsText(snapshot))
                        toasts.show("Details copied", systemImage: "doc.on.doc")
                    } label: {
                        Label("Copy Details", systemImage: "doc.on.doc")
                    }
                    if canEdit {
                        Button {
                            store.duplicateItem(item)
                            toasts.show("Duplicated")
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $editing) {
            ItemEditorView(trip: trip, mode: .edit(item))
        }
        .fullScreenCover(isPresented: $showingLargeCode) {
            LargeCodeView(code: snapshot.confirmationCode)
        }
        .confirmationDialog("Delete “\(snapshot.title)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                lastTitle = nil
                store.deleteItem(item)
                if case .item? = router.path.last {
                    router.path.removeLast()
                }
            }
        } message: {
            if members.filter({ $0.tripId == trip.id }).count > 1 {
                Text("It will be removed for everyone on this trip.")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyCount)
    }

    // MARK: - Blocks

    @ViewBuilder
    private func actionRow(_ item: ItemSnapshot) -> some View {
        let actions = availableActions(item)
        if !actions.isEmpty {
            HStack(spacing: Spacing.s) {
                ForEach(actions) { action in
                    Button(action: action.perform) {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(Palette.accent)
                            Text(action.title)
                                .font(.caption)
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: Radius.action, style: .continuous).fill(Palette.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.accessibilityLabel)
                }
            }
        }
    }

    private func availableActions(_ item: ItemSnapshot) -> [DetailAction] {
        var actions: [DetailAction] = []
        if SystemActions.canOpenDirections(item) {
            let place = item.locationName.isEmpty ? item.title : item.locationName
            actions.append(DetailAction(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond.fill",
                                        accessibilityLabel: "Get directions to \(place)") {
                SystemActions.openDirections(to: item)
            })
        }
        if let phone = item.detail("phone") {
            actions.append(DetailAction(title: "Call", symbol: "phone.fill", accessibilityLabel: "Call \(phone)") {
                SystemActions.call(phone)
            })
        }
        if !item.confirmationCode.isEmpty {
            actions.append(DetailAction(title: "Copy Code", symbol: "doc.on.doc",
                                        accessibilityLabel: "Copy confirmation code") {
                copyCode(item.confirmationCode)
            })
        }
        if let booking = item.detail("bookingUrl") {
            actions.append(DetailAction(title: "Booking", symbol: "safari", accessibilityLabel: "Open booking link") {
                SystemActions.open(booking)
            })
        } else if let website = item.detail("website") {
            actions.append(DetailAction(title: "Website", symbol: "safari", accessibilityLabel: "Open website") {
                SystemActions.open(website)
            })
        }
        return actions
    }

    private func codeBlock(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Confirmation")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            Text(code)
                .font(.wfConfirmationCode)
                .tracking(2)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .accessibilityLabel(Text(code).speechSpellsOutCharacters())
        }
        .wfCard()
        .onTapGesture { copyCode(code) }
        .contextMenu {
            Button {
                copyCode(code)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                showingLargeCode = true
            } label: {
                Label("Show Large", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
        .accessibilityHint("Double-tap to copy")
    }

    private func locationBlock(_ item: ItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let latitude = item.latitude, let longitude = item.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500,
                                                                longitudinalMeters: 1500)),
                    interactionModes: []) {
                    Marker(item.locationName.isEmpty ? item.title : item.locationName, coordinate: coordinate)
                        .tint(item.kind.pinColor)
                }
                .frame(height: 160)
                .background(Palette.surface2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .allowsHitTesting(false)
            }
            addressText(item)
        }
        .contentShape(Rectangle())
        .onTapGesture { SystemActions.openDirections(to: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens directions in Maps")
    }

    private func addressBlock(_ item: ItemSnapshot) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Palette.textSecondary)
            addressText(item)
        }
        .wfCard()
    }

    private func addressText(_ item: ItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if !item.locationName.isEmpty {
                Text(item.locationName)
                    .font(.headline)
            }
            if !item.address.isEmpty {
                Text(item.address)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func detailsList(_ item: ItemSnapshot) -> some View {
        let rows = ItemDetailText.remainingDetails(item)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(rows, id: \.key) { row in
                    LabeledValueRow(label: row.label, value: row.value)
                }
            }
            .wfCard()
        }
    }

    private func reminderRow(_ item: ItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: item.reminderMinutes == nil ? "bell.slash" : "bell.fill")
                    .foregroundStyle(Palette.textSecondary)
                if let minutes = item.reminderMinutes {
                    Text("Reminder: \(TimeFormat.reminderLabel(minutes).lowercasedFirst)")
                } else {
                    Text("No reminder")
                }
            }
            .font(.subheadline)
            if item.reminderMinutes != nil && !permission.isAuthorized {
                HStack {
                    Label("Notifications are off", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                    Spacer()
                    if permission.isDenied {
                        Button("Turn On") { permission.openSystemSettings() }
                            .font(.footnote)
                    }
                }
            }
        }
        .wfCard()
    }

    private func footer(_ item: ItemSnapshot) -> some View {
        Text(updatedText(item))
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func copyCode(_ code: String) {
        SystemActions.copy(code)
        copyCount += 1
        toasts.show("Confirmation code copied", systemImage: "doc.on.doc")
    }

    private func updatedText(_ item: ItemSnapshot) -> String {
        if item.isUnsynced {
            return "Not yet synced"
        }
        let who: String
        if let updatedBy = item.updatedBy {
            if updatedBy == session.userId {
                who = "You"
            } else {
                who = members.first { $0.userId == updatedBy }?.nameForDisplay ?? "A trip member"
            }
        } else {
            who = "You"
        }
        guard let updatedAt = matches.first?.updatedAt, updatedAt > 0 else { return "Updated by \(who)" }
        let date = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000)
        return "Updated by \(who) · \(TimeFormat.lastSynced(date))"
    }

    private func copyDetailsText(_ item: ItemSnapshot) -> String {
        ItemDetailText.plainSummary(item)
    }
}

/// One button in the action row.
struct DetailAction: Identifiable {
    let title: String
    let symbol: String
    let accessibilityLabel: String
    let perform: () -> Void

    var id: String { title }
}

/// Full-screen confirmation code for showing to staff.
struct LargeCodeView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.background.ignoresSafeArea()
            Text(code)
                .font(.system(size: 120, weight: .bold, design: .monospaced))
                .tracking(4)
                .minimumScaleFactor(0.1)
                .lineLimit(1)
                .foregroundStyle(Palette.textPrimary)
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(code).speechSpellsOutCharacters())
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .onTapGesture { dismiss() }
    }
}

extension String {
    /// "At time of event" -> "at time of event".
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(itemId: SampleData.flightId)
    }
    .previewServices()
}
