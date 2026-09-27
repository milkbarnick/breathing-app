import SwiftUI

/// AI Import: one-time consent → paste → loading → review → save (UX spec 3.8).
struct ImportView: View {
    let trip: Trip

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Equatable {
        case consent
        case paste
        case loading
        case review
        case noResults
        case rateLimited
        case forbidden
        case failed
    }

    @State private var step: Step = .paste
    @State private var text = ""
    @State private var rows: [DraftRow] = []
    @State private var requestTask: Task<Void, Never>?
    @State private var showsSlowHint = false
    @State private var editingDraftId: UUID?
    @State private var confirmingDiscard = false
    @State private var addedCount = 0
    @State private var toggleCount = 0

    private var consentKey: String { AppServices.aiConsentKey(userId: session.userId) }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .consent: consentView
                case .paste: pasteView
                case .loading: loadingView
                case .review: reviewView
                case .noResults: noResultsView
                case .rateLimited: errorView(title: "Daily import limit reached",
                                             message: "You've reached today's import limit (30). You can still add plans by hand, and imports reset tomorrow.",
                                             button: "Add Manually", action: { dismiss() })
                case .forbidden: errorView(title: "View only",
                                           message: "You have view-only access to this trip.",
                                           button: "Close", action: { dismiss() })
                case .failed: errorView(title: "Import didn't finish",
                                        message: "Import didn't finish. Your text is still here.",
                                        button: "Try Again", action: { step = .paste })
                }
            }
            .background(Palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .consent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelTapped() }
                    }
                }
            }
            .navigationDestination(item: $editingDraftId) { draftId in
                Group {
                    if let index = rows.firstIndex(where: { $0.id == draftId }) {
                        ItemFormView(trip: trip, initial: rows[index].form, existing: nil, purpose: .draft,
                                     onDraftDone: { updated in updateDraft(draftId, with: updated) },
                                     onClose: {})
                    }
                }
            }
            .confirmationDialog("Discard these drafts?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Reviewing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(step == .review || step == .loading)
        .sensoryFeedback(.success, trigger: addedCount)
        .sensoryFeedback(.selection, trigger: toggleCount)
        .onAppear {
            if !UserDefaults.standard.bool(forKey: consentKey) {
                step = .consent
            }
        }
    }

    private var title: String {
        switch step {
        case .consent: return "Import with AI"
        case .review: return rows.count == 1 ? "Review 1 Plan" : "Review \(rows.count) Plans"
        default: return "Import Plans"
        }
    }

    // MARK: - Step 0: consent

    private var consentView: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.accent)
                    .padding(.top, Spacing.xxl)
                    .accessibilityHidden(true)
                Text("Import with AI")
                    .font(.wfSheetTitle)
                Text("Pasted text is sent to Anthropic to extract your plans. Wayfare's server passes it to Anthropic's Claude, which returns draft plans for you to review. Only paste text you're comfortable sharing, and remove anything you don't need, like payment details.")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if let url = AppConfig.privacyPolicyURL {
                    Link("Learn more", destination: url)
                }
                Button {
                    UserDefaults.standard.set(true, forKey: consentKey)
                    step = .paste
                } label: {
                    Text("Agree & Continue").frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
                .padding(.top, Spacing.l)
                Button("Not Now") { dismiss() }
            }
            .padding(Spacing.xxl)
        }
    }

    // MARK: - Step 1: paste

    private var pasteView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Paste a booking confirmation (flight, hotel, restaurant, tickets). Wayfare will draft the plans for you to review. Nothing is added until you say so.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.first ?? ""
                    Task { @MainActor in
                        text = pasted
                    }
                }
                .buttonBorderShape(.capsule)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.s)
                        .frame(minHeight: 240)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(Palette.surface))
                        .accessibilityLabel("Confirmation text")
                    if text.isEmpty {
                        Text("Or type/paste here…")
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.l)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    Spacer()
                    Text("\(text.count.formatted()) / \(ImportReview.maxCharacters.formatted())")
                        .font(.wfCounter)
                        .foregroundStyle(text.count > ImportReview.maxCharacters ? Palette.danger : Palette.textSecondary)
                        .contentTransition(.numericText())
                }
                Label("The text is sent to Wayfare's server and processed by Anthropic's Claude to find your plans. Don't paste passwords or card numbers.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Spacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.xs) {
                Button {
                    findPlans()
                } label: {
                    Label("Find Plans", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
                .disabled(!canSubmit)
                if !network.isOnline {
                    Text("Import needs a connection")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Spacing.l)
            .background(Palette.background)
        }
    }

    private var canSubmit: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text.count <= ImportReview.maxCharacters && network.isOnline
    }

    // MARK: - Step 2: loading

    private var loadingView: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            if reduceMotion {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.accent)
                ProgressView()
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.accent)
                    .symbolEffect(.pulse)
            }
            Text("Reading your confirmation…")
                .font(.headline)
            if showsSlowHint {
                Text("This can take up to 30 seconds.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .task {
            showsSlowHint = false
            try? await Task.sleep(for: .seconds(6))
            showsSlowHint = true
        }
    }

    // MARK: - Step 3: review

    private var reviewView: some View {
        List {
            Section {
                ForEach($rows) { $row in
                    draftRow($row)
                }
            } header: {
                Text("Check the details. Uncheck anything you don't want.")
                    .textCase(nil)
            } footer: {
                Text("Nothing here? Try pasting the full email, including dates.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            let count = rows.filter(\.included).count
            Button {
                addPlans()
            } label: {
                Text(count == 1 ? "Add 1 Plan" : "Add \(count) Plans").frame(maxWidth: .infinity)
            }
            .wfPrimaryButton()
            .disabled(count == 0)
            .padding(Spacing.l)
            .background(Palette.background)
        }
    }

    private func draftRow(_ row: Binding<DraftRow>) -> some View {
        let value = row.wrappedValue
        return HStack(alignment: .top, spacing: Spacing.m) {
            Button {
                row.wrappedValue.included.toggle()
                toggleCount += 1
            } label: {
                Image(systemName: value.included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(value.included ? Palette.accent : Palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include")
            .accessibilityAddTraits(value.included ? .isSelected : [])

            Button {
                editingDraftId = value.id
            } label: {
                HStack(alignment: .top, spacing: Spacing.m) {
                    KindIcon(kind: value.form.kind)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(value.form.effectiveTitle.isEmpty ? value.form.kind.displayName : value.form.effectiveTitle)
                            .font(.wfRowTitle)
                            .foregroundStyle(Palette.textPrimary)
                        Text(ImportReview.whenText(value.form))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(value.hasWarnings ? Palette.warning : Palette.textSecondary)
                        ForEach(value.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Palette.warning)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(value.included ? .isSelected : [])
        .accessibilityAction(named: "Toggle include") {
            row.wrappedValue.included.toggle()
        }
    }

    // MARK: - Errors

    private var noResultsView: some View {
        ContentUnavailableView {
            Label("No plans found", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("We couldn't find bookings in that text. Try pasting the whole confirmation email.")
        } actions: {
            Button("Edit Text") { step = .paste }
                .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func cancelTapped() {
        switch step {
        case .loading:
            requestTask?.cancel()
            requestTask = nil
            step = .paste
        case .review:
            confirmingDiscard = true
        default:
            dismiss()
        }
    }

    private func findPlans() {
        guard canSubmit, UserDefaults.standard.bool(forKey: consentKey) else { return }
        step = .loading
        let submitted = text
        let context = ImportReview.TripContext(start: trip.startDay, end: trip.endDay, timeZone: trip.timeZone)
        let existing = store.liveItems(tripId: trip.id).map(\.snapshot)
        requestTask = Task {
            do {
                let drafts = try await services.api.importDrafts(tripId: trip.id, text: submitted)
                guard !Task.isCancelled else { return }
                rows = ImportReview.rows(from: drafts, trip: context, existing: existing)
                step = rows.isEmpty ? .noResults : .review
            } catch let error as APIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                if error.isRateLimited {
                    step = .rateLimited
                } else if error.isForbidden {
                    step = .forbidden
                } else {
                    step = .failed
                }
            } catch {
                if !Task.isCancelled { step = .failed }
            }
        }
    }

    private func updateDraft(_ id: UUID, with form: ItemFormState) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].form = form
    }

    private func addPlans() {
        let forms = rows.filter(\.included).map(\.form)
        guard !forms.isEmpty else { return }
        let created = store.addDrafts(forms, tripId: trip.id)
        addedCount += 1
        if let earliest = created.min(by: { $0.startAt < $1.startAt }) {
            router.timelineFocus = TimelineFocus(tripId: trip.id, day: nil, itemId: earliest.id)
        }
        toasts.show(created.count == 1 ? "Added 1 plan" : "Added \(created.count) plans")
        dismiss()
    }
}
