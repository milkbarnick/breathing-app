import SwiftUI

/// New / Edit Trip sheet (UX spec 3.2).
struct TripEditorView: View {
    /// nil = New Trip.
    let trip: Trip?

    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(NotificationPermission.self) private var permission

    @State private var form: TripFormState
    @State private var original: TripFormState
    @State private var suggestedZone: String?
    @State private var emojiInput = ""
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var saveCount = 0
    @FocusState private var titleFocused: Bool

    init(trip: Trip?) {
        self.trip = trip
        let initial = trip.map { TripFormState(trip: $0) } ?? TripFormState.newTrip()
        _form = State(initialValue: initial)
        _original = State(initialValue: initial)
    }

    private var isNew: Bool { trip == nil }
    private var isDirty: Bool { form != original }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    coverPreview
                }
                .listRowBackground(Color.clear)

                Section("Trip") {
                    TextField("e.g. Lisbon & Porto", text: $form.title)
                        .focused($titleFocused)
                        .accessibilityLabel("Title")
                    NavigationLink {
                        LocationSearchView(mode: .destination, onPick: pickDestination, onUseText: { text in
                            form.destination = text
                        })
                    } label: {
                        LabeledContent("Destination") {
                            Text(form.destination.isEmpty ? "Add" : form.destination)
                                .foregroundStyle(form.destination.isEmpty ? Palette.textSecondary : Palette.textPrimary)
                        }
                    }
                }

                Section {
                    DatePicker("Start", selection: startBinding, displayedComponents: .date)
                    DatePicker("End", selection: endBinding, in: startDate..., displayedComponents: .date)
                } header: {
                    Text("Dates")
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(TimeFormat.tripLength(form.startDay, form.endDay))
                            .monospacedDigit()
                        if outsideCount > 0 {
                            Text("\(outsideCount) plans will be outside the new dates. They'll stay in the timeline under Before/After trip.")
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }
                .environment(\.timeZone, .utc)

                Section {
                    NavigationLink {
                        TimeZonePickerView(selection: $form.timeZone, suggested: [suggestedZone].compactMap { $0 },
                                           onPick: { _ in form.timeZoneChosenManually = true })
                    } label: {
                        LabeledContent {
                            Text(TimeFormat.zoneLabel(form.timeZone))
                        } label: {
                            Label("Time Zone", systemImage: "globe")
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Your timeline is organized by days in this time zone.")
                        if !isNew && form.timeZone != original.timeZone {
                            Text("Days will be regrouped in the new time zone. Item times don't change.")
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }

                Section("Cover") {
                    CoverPicker(emoji: $form.coverEmoji, colorHex: $form.colorHex, emojiInput: $emojiInput,
                                onEmojiPicked: { form.emojiChosenManually = true })
                }

                Section("Notes") {
                    TextField("Notes for everyone on this trip", text: $form.notes, axis: .vertical)
                        .lineLimit(3...10)
                }

                if let trip {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Text(store.role(for: trip) == .owner ? "Delete Trip" : "Leave Trip")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(isNew ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save)
                        .fontWeight(.bold)
                        .disabled(!form.isValid)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(isOwner ? "Delete Trip" : "Leave Trip", role: .destructive) {
                    if let trip {
                        store.deleteOrLeave(trip)
                        dismiss()
                        router.popToRoot()
                    }
                }
            } message: {
                Text(deleteMessage)
            }
            .sensoryFeedback(.success, trigger: saveCount)
            .onAppear {
                if isNew { titleFocused = true }
            }
        }
    }

    // MARK: - Pieces

    private var coverPreview: some View {
        VStack(spacing: Spacing.s) {
            CoverTile(emoji: form.coverEmoji, colorHex: form.colorHex, size: 88)
            Text(form.trimmedTitle.isEmpty ? "New Trip" : form.trimmedTitle)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var startDate: Date { form.startDay.startDate(in: .utc) ?? Date() }

    private var startBinding: Binding<Date> {
        Binding(
            get: { form.startDay.startDate(in: .utc) ?? Date() },
            set: { form.setStartDay(CalendarDay(date: $0, in: .utc)) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { form.endDay.startDate(in: .utc) ?? Date() },
            set: { form.endDay = max(CalendarDay(date: $0, in: .utc), form.startDay) }
        )
    }

    /// Items that would fall outside the edited dates.
    private var outsideCount: Int {
        guard let trip, form.startDay != original.startDay || form.endDay != original.endDay else { return 0 }
        let zone = TimeZone.resolve(form.timeZone)
        return store.liveItems(tripId: trip.id).filter { item in
            let day = DayGrouping.groupingDay(for: item.snapshot, tripZone: zone)
            return day < form.startDay || day > form.endDay
        }.count
    }

    private var isOwner: Bool {
        guard let trip else { return true }
        return store.role(for: trip) == .owner
    }

    private var deleteTitle: String {
        let title = trip?.displayTitle ?? ""
        return isOwner ? "Delete “\(title)”?" : "Leave “\(title)”?"
    }

    private var deleteMessage: String {
        guard let trip else { return "" }
        if isOwner {
            let count = store.liveItems(tripId: trip.id).count
            return "This deletes the trip and all \(count) plans for everyone it's shared with. This can't be undone."
        }
        return "You'll lose access until someone invites you again."
    }

    // MARK: - Actions

    private func pickDestination(_ place: ResolvedPlace) {
        form.destination = place.shortName
        if let zone = place.timeZone {
            suggestedZone = zone
            if !form.timeZoneChosenManually {
                form.timeZone = zone
            }
        }
        if !form.emojiChosenManually, let code = place.countryCode, let flag = EmojiText.flag(forCountryCode: code) {
            form.coverEmoji = flag
        }
    }

    private func save() {
        guard form.isValid else { return }
        saveCount += 1
        if let trip {
            store.updateTrip(trip, from: form)
            dismiss()
            return
        }
        let created = store.createTrip(from: form)
        let createdId = created.id
        let request = PrimingRequest.firstTrip(tripTitle: created.displayTitle)
        let shouldPrime = permission.shouldPrime(.firstTrip)
        dismiss()
        router.path = [.trip(createdId)]
        if shouldPrime {
            permission.markPrimed(.firstTrip)
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if router.sheet == nil {
                    router.sheet = .priming(request)
                }
            }
        }
    }
}

/// Emoji + color cover picker (design system 7 and 9).
struct CoverPicker: View {
    @Binding var emoji: String
    @Binding var colorHex: String
    @Binding var emojiInput: String
    var onEmojiPicked: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(EmojiText.quickPicks, id: \.self) { pick in
                        Button {
                            emoji = pick
                            onEmojiPicked()
                        } label: {
                            Text(pick)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.band, style: .continuous)
                                        .fill(pick == emoji ? Palette.accentTint : Palette.surface2)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cover emoji \(pick)")
                    }
                }
            }

            HStack {
                Text(emoji)
                    .font(.title)
                    .accessibilityHidden(true)
                TextField("Choose Emoji", text: $emojiInput)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Cover emoji, \(emoji)")
                    .onChange(of: emojiInput) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        if let picked = EmojiText.lastEmoji(in: newValue) {
                            emoji = picked
                            onEmojiPicked()
                        }
                        // Non-emoji input is rejected; the field always clears.
                        emojiInput = ""
                    }
            }

            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(CoverColor.all) { cover in
                    let selected = cover.hex.caseInsensitiveCompare(colorHex) == .orderedSame
                    Button {
                        colorHex = cover.hex
                    } label: {
                        Circle()
                            .fill(cover.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selected {
                                    Circle().stroke(Palette.textPrimary, lineWidth: 3).frame(width: 42, height: 42)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? "\(cover.name), selected" : cover.name)
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview("New Trip") {
    TripEditorView(trip: nil)
        .previewServices()
}
