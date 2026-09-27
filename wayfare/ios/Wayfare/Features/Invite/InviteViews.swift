import SwiftUI

/// Joining sheet for `wayfare://invite/<code>` and Join with Code (UX spec 3.7).
struct AcceptInviteView: View {
    let code: String

    @Environment(AppServices.self) private var services
    @Environment(TripStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(NetworkMonitor.self) private var network
    @Environment(NotificationPermission.self) private var permission
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case joining
        case joined(TripDTO, alreadyMember: Bool)
        case invalid
        case offline
        case failed
    }

    @State private var phase: Phase = .joining
    @State private var successCount = 0

    var body: some View {
        VStack(spacing: Spacing.l) {
            switch phase {
            case .joining:
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("Joining trip…")
                    .font(.headline)
                Spacer()
            case .joined(let trip, let alreadyMember):
                CoverTile(emoji: trip.coverEmoji, colorHex: trip.colorHex, size: 88)
                Text(alreadyMember ? "You're already on this trip" : "You're in!")
                    .font(.wfSheetTitle)
                VStack(spacing: Spacing.xxs) {
                    Text(trip.title)
                        .font(.headline)
                    if let start = CalendarDay(string: trip.startDate), let end = CalendarDay(string: trip.endDate) {
                        Text(TimeFormat.dateRange(start, end, includeYear: true))
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    openTrip(trip)
                } label: {
                    Text("Open Trip").frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
            case .invalid:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.textSecondary)
                Text("This invite has expired or isn't valid")
                    .font(.wfSheetTitle)
                    .multilineTextAlignment(.center)
                Text("Ask the sender for a new link. Invites last 7 days.")
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button {
                    router.sheet = .joinWithCode(prefill: nil)
                } label: {
                    Text("Enter a Code").frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
                Button("Close") { dismiss() }
            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.textSecondary)
                Text("Joining a trip needs a connection. We'll keep this invite and try again when you're online.")
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button("Close") { dismiss() }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.danger)
                Text("Couldn't join the trip. Try again.")
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button {
                    Task { await accept() }
                } label: {
                    Text("Try Again").frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
                Button("Close") { dismiss() }
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: successCount)
        .task { await accept() }
        .onChange(of: network.isOnline) { _, online in
            if online && phase == .offline {
                Task { await accept() }
            }
        }
    }

    private func accept() async {
        phase = .joining
        do {
            let trip = try await services.api.acceptInvite(code: code)
            let wasLocal = store.tripExists(trip.id)
            store.upsertAcceptedTrip(trip)
            router.clearPendingInvite()
            phase = .joined(trip, alreadyMember: wasLocal)
            successCount += 1
            // Pull items and members right away.
            sync.requestSync()
        } catch let error as APIError {
            if error.isNotFound {
                router.clearPendingInvite()
                phase = .invalid
            } else if error.isConnectivity {
                phase = .offline
            } else {
                phase = .failed
            }
        } catch {
            phase = .failed
        }
    }

    private func openTrip(_ trip: TripDTO) {
        let tripId = trip.id
        let tripTitle = trip.title
        let ownerName = store.members(tripId: tripId).first { $0.role == .owner }?.nameForDisplay ?? "the owner"
        let shouldPrime = permission.shouldPrime(.joinedTrip)
        dismiss()
        router.show(tripId: tripId)
        if shouldPrime {
            permission.markPrimed(.joinedTrip)
            let request = PrimingRequest.joinedTrip(ownerName: ownerName, tripTitle: tripTitle)
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if router.sheet == nil {
                    router.sheet = .priming(request)
                }
            }
        }
    }
}

/// Join with Code: one monospaced 8-character field (UX spec 3.7).
struct JoinWithCodeView: View {
    var prefill: String?

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    init(prefill: String? = nil) {
        self.prefill = prefill
    }

    private var normalized: String { AppRouter.normalizeCode(code) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code, prompt: Text("AB12CD34"))
                        .font(.title2.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .accessibilityLabel("Invite code, 8 characters")
                        .onChange(of: code) { _, newValue in
                            let cleaned = String(AppRouter.normalizeCode(newValue).prefix(8))
                            if cleaned != newValue { code = cleaned }
                        }
                        .onSubmit(join)
                } footer: {
                    Text("Ask the person who shared the trip for their 8-character code.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Join with Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", action: join)
                        .fontWeight(.bold)
                        .disabled(normalized.count != 8)
                }
            }
            .onAppear {
                if let prefill { code = prefill }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        guard normalized.count == 8 else { return }
        router.setPendingInvite(normalized)
        router.sheet = .acceptInvite(code: normalized)
    }
}
