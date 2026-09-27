import MapKit
import SwiftData
import SwiftUI

/// The item form itself. Used inside the Add/Edit sheet and, in `.draft` purpose, pushed from AI import review.
struct ItemFormView: View {
    enum Purpose {
        case add
        case edit
        /// Editing an AI draft in memory: "Done" returns the form, nothing is saved.
        case draft
    }

    let trip: Trip
    let existing: Item?
    let purpose: Purpose
    var onDraftDone: ((ItemFormState) -> Void)?
    var onClose: () -> Void

    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(NotificationPermission.self) private var permission
    @Environment(\.dismiss) private var dismiss

    @Query private var liveMatches: [Item]
    @Query private var members: [Member]

    @State private var form: ItemFormState
    @State private var original: ItemFormState
    @State private var originalUpdatedAt: Int
    @State private var conflictHandled = false
    @State private var deletedRemotely = false
    @State private var deletingSelf = false
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var priming: PrimingRequest?
    @State private var saveCount = 0

    init(trip: Trip, initial: ItemFormState, existing: Item?, purpose: Purpose,
         onDraftDone: ((ItemFormState) -> Void)? = nil, onClose: @escaping () -> Void) {
        self.trip = trip
        self.existing = existing
        self.purpose = purpose
        self.onDraftDone = onDraftDone
        self.onClose = onClose
        _form = State(initialValue: initial)
        _original = State(initialValue: initial)
        _originalUpdatedAt = State(initialValue: existing?.updatedAt ?? 0)
        let id = existing?.id ?? "-"
        let tripId = trip.id
        _liveMatches = Query(filter: #Predicate<Item> { $0.id == id })
        _members = Query(filter: #Predicate<Member> { $0.tripId == tripId })
    }

    private var isDirty: Bool { form != original }
    private var kind: ItemKind { form.kind }

    var body: some View {
        Form {
            if let conflict = conflictName {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Label("\(conflict) just changed this plan.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            Button("Review") { reloadFromServer() }
                                .buttonStyle(.bordered)
                            Button("Keep Mine") { conflictHandled = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section {
                if purpose != .add {
                    Picker("Type", selection: $form.kind) {
                        ForEach(ItemKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }
                LabeledContent("Title") {
                    TextField("Title", text: $form.title, prompt: Text(kind.titlePlaceholder))
                        .multilineTextAlignment(.trailing)
                }
            }

            kindSection

            whenSection

            if kind != .note {
                locationSection
                Section {
                    LabeledContent("Confirmation") {
                        TextField("Confirmation", text: $form.confirmationCode, prompt: Text("e.g. ABC123"))
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }
            } else {
                Section {
                    DisclosureGroup("More") {
                        locationRow
                    }
                }
            }

            reminderSection

            Section("Notes") {
                TextField("Notes", text: $form.notes, prompt: Text("Anything else to remember"), axis: .vertical)
                    .lineLimit(3...10)
            }

            if purpose == .edit {
                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Text("Delete Item").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar { toolbar }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { close() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(form.effectiveTitle)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteItem)
        } message: {
            if members.count > 1 {
                Text("It will be removed for everyone on this trip.")
            }
        }
        .alert("This plan was deleted by someone else.", isPresented: $deletedRemotely) {
            Button("Save as New") { saveAsNew() }
            Button("Discard", role: .cancel) { close() }
        }
        .sheet(item: $priming) { request in
            PrimingSheet(request: request)
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .onChange(of: liveMatches.isEmpty) { _, isEmpty in
            if isEmpty && existing != nil && purpose == .edit && !deletingSelf {
                deletedRemotely = true
            }
        }
        .onChange(of: form.reminderMinutes) { _, minutes in
            guard let minutes, permission.shouldPrime(.firstReminder) else { return }
            permission.markPrimed(.firstReminder)
            priming = .firstReminder(minutes: minutes, itemTitle: form.effectiveTitle)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if purpose != .draft || isDirty {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isDirty { confirmingDiscard = true } else { close() }
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(saveTitle, action: save)
                .fontWeight(.bold)
                .disabled(!form.isValid)
        }
    }

    private var saveTitle: String {
        switch purpose {
        case .add: return "Add"
        case .edit: return "Save"
        case .draft: return "Done"
        }
    }

    private var navigationTitle: String {
        switch purpose {
        case .add: return "New \(kind.displayName)"
        case .edit: return "Edit \(kind.displayName)"
        case .draft: return "Review \(kind.displayName)"
        }
    }

    // MARK: - Kind-specific

    @ViewBuilder
    private var kindSection: some View {
        switch kind {
        case .flight:
            Section("Flight") {
                textRow("Airline", key: "airline", prompt: "e.g. TAP")
                textRow("Flight number", key: "flightNumber", prompt: "e.g. TP202", uppercase: true, monospaced: true)
                textRow("From", key: "fromCode", prompt: "JFK", uppercase: true, monospaced: true, maxLength: 3)
                textRow("To", key: "toCode", prompt: "LIS", uppercase: true, monospaced: true, maxLength: 3)
                textRow("Terminal", key: "terminal", prompt: "Optional")
                textRow("Gate", key: "gate", prompt: "Optional")
                textRow("Seat", key: "seat", prompt: "e.g. 14A", uppercase: true)
                NavigationLink {
                    LocationSearchView(mode: .airport, region: nil, onPick: applyArrivalPlace, onUseText: { _ in })
                } label: {
                    LabeledContent("Arrival Airport") {
                        Text(form.endTimeZone.map { TimeFormat.city(forZoneIdentifier: $0) } ?? "Sets arrival time zone")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        case .lodging:
            Section("Stay") {
                textRow("Room type", key: "roomType", prompt: "Optional")
                textRow("Phone", key: "phone", prompt: "Optional", keyboard: .phonePad)
                textRow("Check-in time", key: "checkInTime", prompt: "e.g. from 15:00")
                textRow("Check-out time", key: "checkOutTime", prompt: "e.g. until 11:00")
            }
        case .transport:
            Section("Journey") {
                Picker("Mode", selection: modeBinding) {
                    ForEach(TransportMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                textRow("Operator", key: "operator", prompt: "e.g. CP")
                textRow("From", key: "fromName", prompt: "e.g. Lisboa Santa Apolónia")
                textRow("To", key: "toName", prompt: "e.g. Porto Campanhã")
                textRow("Seat", key: "seat", prompt: "Optional")
                NavigationLink {
                    LocationSearchView(mode: .place, region: searchRegion, onPick: applyArrivalPlace,
                                       onUseText: { text in form.setDetail("toName", text) })
                } label: {
                    LabeledContent("Arrival") {
                        Text(form.detail("toName").isEmpty ? "Search" : form.detail("toName"))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        case .activity, .food:
            Section(kind == .food ? "Reservation" : "Booking") {
                textRow("Phone", key: "phone", prompt: "Optional", keyboard: .phonePad)
                textRow("Website", key: "website", prompt: "Optional", keyboard: .URL, noAutocaps: true)
                textRow("Booking link", key: "bookingUrl", prompt: "Optional", keyboard: .URL, noAutocaps: true)
                Stepper(value: partySizeBinding, in: 0...20) {
                    LabeledContent("Party size") {
                        Text(partySizeBinding.wrappedValue == 0 ? "Not set" : "\(partySizeBinding.wrappedValue)")
                            .monospacedDigit()
                    }
                }
            }
        case .note:
            EmptyView()
        }
    }

    // MARK: - When

    private var whenSection: some View {
        Section {
            if form.showsAllDayToggle {
                Toggle("All day", isOn: $form.allDay)
            }
            DatePicker(kind.startLabel, selection: $form.startAt,
                       displayedComponents: form.allDay ? [.date] : [.date, .hourAndMinute])
                .environment(\.timeZone, form.startZone)
            NavigationLink {
                TimeZonePickerView(selection: startZoneBinding, suggested: [trip.timeZone],
                                   title: kind == .flight || kind == .transport ? "Departure Time Zone" : "Time Zone",
                                   onPick: { _ in form.startZoneChosenManually = true })
            } label: {
                LabeledContent {
                    Text(TimeFormat.zoneLabel(form.startTimeZone, at: form.startAt))
                } label: {
                    Label(form.hasOwnEndZone ? "Departure time zone" : "Time Zone", systemImage: "globe")
                }
            }
            .accessibilityLabel("Start time zone, \(TimeFormat.city(forZoneIdentifier: form.startTimeZone))")

            if form.endAt != nil || form.endIsRequired {
                DatePicker(kind.endLabel, selection: endBinding,
                           displayedComponents: form.allDay ? [.date] : [.date, .hourAndMinute])
                    .environment(\.timeZone, form.endZone)
                if form.hasOwnEndZone {
                    NavigationLink {
                        TimeZonePickerView(selection: endZoneBinding, suggested: [trip.timeZone, form.startTimeZone],
                                           title: "Arrival Time Zone")
                    } label: {
                        LabeledContent {
                            Text(TimeFormat.zoneLabel(form.endTimeZone ?? form.startTimeZone, at: form.endAt ?? form.startAt))
                        } label: {
                            Label("Arrival time zone", systemImage: "globe")
                        }
                    }
                }
                if !form.endIsRequired {
                    Button("Remove \(kind.endLabel.lowercased()) time", role: .destructive) {
                        form.endAt = nil
                    }
                }
            } else {
                Button {
                    form.endAt = form.startAt.addingTimeInterval(kind == .flight ? 3 * 3600 : 3600)
                } label: {
                    Label(kind == .flight || kind == .transport ? "Add arrival time" : "Add end time",
                          systemImage: "plus.circle")
                }
            }
            if let error = form.endError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .accessibilityAddTraits(.isStaticText)
            }
        } header: {
            Text("When")
        } footer: {
            outsideTripFooter
        }
    }

    @ViewBuilder
    private var outsideTripFooter: some View {
        let day = form.allDay ? CalendarDay(date: form.startAt, in: form.startZone) : CalendarDay(date: form.startAt, in: trip.tz)
        if purpose != .draft && (day < trip.startDay || day > trip.endDay) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("This is outside the trip dates (\(TimeFormat.dateRange(trip.startDay, trip.endDay))).")
                    .foregroundStyle(Palette.warning)
                Button("Extend Trip") {
                    store.extendTrip(trip, toInclude: day)
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        Section {
            locationRow
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        NavigationLink {
            LocationSearchView(mode: kind == .flight ? .airport : .place, region: searchRegion,
                               onPick: applyStartPlace,
                               onUseText: { text in
                                   form.locationName = text
                                   form.address = ""
                                   form.latitude = nil
                                   form.longitude = nil
                               })
        } label: {
            if form.locationName.isEmpty {
                Label(locationLabel, systemImage: "mappin.and.ellipse")
            } else {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(form.locationName)
                        .foregroundStyle(Palette.textPrimary)
                    if !form.address.isEmpty {
                        Text(form.address)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        if !form.locationName.isEmpty {
            Button(role: .destructive) {
                form.locationName = ""
                form.address = ""
                form.latitude = nil
                form.longitude = nil
            } label: {
                Label("Clear location", systemImage: "xmark.circle.fill")
            }
        }
    }

    private var locationLabel: String {
        switch kind {
        case .flight: return "Departure Airport"
        case .transport: return "Departure Station / Stop"
        default: return "Add Location"
        }
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        Section {
            Picker("Reminder", selection: $form.reminderMinutes) {
                ForEach(TimeFormat.reminderPresets, id: \.self) { minutes in
                    Text(TimeFormat.reminderLabel(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            if form.reminderMinutes != nil && !permission.isAuthorized {
                HStack {
                    Label("Notifications are off", systemImage: "bell.slash")
                        .foregroundStyle(Palette.warning)
                    Spacer()
                    Button("Turn On") {
                        if permission.isNotDetermined {
                            priming = .firstReminder(minutes: form.reminderMinutes ?? 0, itemTitle: form.effectiveTitle)
                        } else {
                            permission.openSystemSettings()
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline)
            }
        } footer: {
            if kind == .lodging {
                Text("Lodging reminders are relative to check-in.")
            }
        }
    }

    // MARK: - Bindings

    private func textRow(_ label: String, key: String, prompt: String, uppercase: Bool = false,
                         monospaced: Bool = false, maxLength: Int? = nil,
                         keyboard: UIKeyboardType = .default, noAutocaps: Bool = false) -> some View {
        LabeledContent(label) {
            TextField(label, text: detailBinding(key, uppercase: uppercase, maxLength: maxLength), prompt: Text(prompt))
                .font(monospaced ? .body.monospaced() : .body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(uppercase ? .characters : (noAutocaps ? .never : .sentences))
                .autocorrectionDisabled(uppercase || noAutocaps)
                .multilineTextAlignment(.trailing)
        }
    }

    private func detailBinding(_ key: String, uppercase: Bool, maxLength: Int?) -> Binding<String> {
        Binding(
            get: { form.detail(key) },
            set: { newValue in
                var value = uppercase ? newValue.uppercased() : newValue
                if let maxLength, value.count > maxLength {
                    value = String(value.prefix(maxLength))
                }
                form.setDetail(key, value)
            }
        )
    }

    private var modeBinding: Binding<TransportMode> {
        Binding(
            get: { TransportMode(rawValue: form.detail("mode")) ?? .train },
            set: { form.setDetail("mode", $0.rawValue) }
        )
    }

    private var partySizeBinding: Binding<Int> {
        Binding(
            get: { Int(form.detail("partySize")) ?? 0 },
            set: { form.setDetail("partySize", $0 == 0 ? "" : String($0)) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { form.endAt ?? form.startAt },
            set: { form.endAt = $0 }
        )
    }

    /// Changing the zone keeps the wall-clock time the user typed.
    private var startZoneBinding: Binding<String> {
        Binding(
            get: { form.startTimeZone },
            set: { newValue in setStartZone(newValue) }
        )
    }

    private var endZoneBinding: Binding<String> {
        Binding(
            get: { form.endTimeZone ?? form.startTimeZone },
            set: { newValue in
                if let end = form.endAt {
                    form.endAt = WallClock.keeping(end, from: form.endZone, to: TimeZone.resolve(newValue))
                }
                form.endTimeZone = newValue
            }
        )
    }

    private func setStartZone(_ identifier: String) {
        let oldZone = form.startZone
        let newZone = TimeZone.resolve(identifier)
        form.startAt = WallClock.keeping(form.startAt, from: oldZone, to: newZone)
        if !form.hasOwnEndZone || form.endTimeZone == nil, let end = form.endAt {
            form.endAt = WallClock.keeping(end, from: oldZone, to: newZone)
        }
        form.startTimeZone = identifier
    }

    private var searchRegion: MKCoordinateRegion? {
        trip.searchRegion(items: store.liveItems(tripId: trip.id).map(\.snapshot))
    }

    // MARK: - Place handling

    private func applyStartPlace(_ place: ResolvedPlace) {
        form.locationName = place.name
        form.address = place.address
        form.latitude = place.latitude
        form.longitude = place.longitude
        if kind == .flight, form.detail("fromCode").isEmpty, let code = WallClock.airportCode(in: place.name) {
            form.setDetail("fromCode", code)
        }
        if let zone = place.timeZone, !form.startZoneChosenManually, zone != form.startTimeZone {
            setStartZone(zone)
            toasts.show("Time zone set to \(TimeFormat.city(forZoneIdentifier: zone))", systemImage: "globe")
        }
    }

    /// Arrival search only sets the arrival zone (and fills the code/name when empty).
    private func applyArrivalPlace(_ place: ResolvedPlace) {
        if let zone = place.timeZone {
            if let end = form.endAt {
                form.endAt = WallClock.keeping(end, from: form.endZone, to: TimeZone.resolve(zone))
            }
            form.endTimeZone = zone
        }
        if kind == .flight {
            if form.detail("toCode").isEmpty, let code = WallClock.airportCode(in: place.name) {
                form.setDetail("toCode", code)
            }
        } else if kind == .transport, form.detail("toName").isEmpty {
            form.setDetail("toName", place.name)
        }
    }

    // MARK: - Conflicts

    /// Name of the collaborator whose newer version arrived while editing, or nil.
    private var conflictName: String? {
        guard purpose == .edit, !conflictHandled, let current = liveMatches.first,
              current.updatedAt != originalUpdatedAt, !current.needsPush,
              let updatedBy = current.updatedBy, updatedBy != session.userId else { return nil }
        return members.first { $0.userId == updatedBy }?.nameForDisplay ?? "Someone"
    }

    private func reloadFromServer() {
        guard let current = liveMatches.first else { return }
        let reloaded = ItemFormState(item: current)
        form = reloaded
        original = reloaded
        originalUpdatedAt = current.updatedAt
        conflictHandled = false
    }

    // MARK: - Actions

    private func save() {
        guard form.isValid else { return }
        switch purpose {
        case .draft:
            onDraftDone?(form)
            original = form
            dismiss()
        case .add, .edit:
            let item = store.saveItem(form, existing: existing, tripId: trip.id)
            saveCount += 1
            router.timelineFocus = TimelineFocus(tripId: trip.id, day: nil, itemId: item.id)
            original = form
            close()
        }
    }

    private func saveAsNew() {
        let item = store.saveItem(form, existing: nil, tripId: trip.id)
        router.timelineFocus = TimelineFocus(tripId: trip.id, day: nil, itemId: item.id)
        original = form
        close()
    }

    private func deleteItem() {
        guard let existing else { return }
        deletingSelf = true
        let deletedId = existing.id
        store.deleteItem(existing)
        original = form
        close()
        if case .item(let id)? = router.path.last, id == deletedId {
            router.path.removeLast()
        }
    }

    private func close() {
        if purpose == .draft {
            dismiss()
        } else {
            onClose()
        }
    }
}
