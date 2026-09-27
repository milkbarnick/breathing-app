import SwiftData
import SwiftUI

/// Share & Members sheet (UX spec 3.6).
struct ShareTripView: View {
    let tripId: String

    @Environment(AppServices.self) private var services
    @Environment(TripStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var trips: [Trip]
    @Query private var members: [Member]
    @Query private var dirtyItems: [Item]

    @State private var inviteRole: MemberRole = .editor
    @State private var invite: InviteDTO?
    @State private var isCreating = false
    @State private var inviteError: String?
    @State private var removing: Member?
    @State private var removeError: String?
    @State private var confirmingLeave = false
    @State private var successCount = 0
    @State private var errorCount = 0

    init(tripId: String) {
        let id = tripId.lowercased()
        self.tripId = id
        _trips = Query(filter: #Predicate<Trip> { $0.id == id })
        _members = Query(filter: #Predicate<Member> { $0.tripId == id })
        _dirtyItems = Query(filter: #Predicate<Item> { $0.tripId == id && $0.needsPush == true })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let trip = trips.first {
                    content(trip)
                } else {
                    ContentUnavailableView("Trip unavailable", systemImage: "suitcase.rolling")
                }
            }
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: errorCount)
    }

    private func content(_ trip: Trip) -> some View {
        let myRole = store.role(for: trip)
        return List {
            if myRole.canEdit {
                inviteSection(trip)
            }

            Section {
                ForEach(sortedMembers, id: \.key) { member in
                    memberRow(member, trip: trip, myRole: myRole)
                }
                if members.isEmpty {
                    Text("Members appear after the trip syncs.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let removeError {
                    Text(removeError)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                Text(members.count == 1 ? "1 person" : "\(members.count) people")
            } footer: {
                if myRole == .owner {
                    Text("To change someone's role, remove them and send a new invite.")
                }
            }

            if trip.needsPush || !dirtyItems.isEmpty {
                Section {
                    Label("Some of your changes haven't synced yet. Invitees will see them once you're online.",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .onChange(of: inviteRole) { _, _ in
            invite = nil
            inviteError = nil
        }
        .confirmationDialog(removeTitle, isPresented: isConfirmingRemove, titleVisibility: .visible,
                            presenting: removing) { member in
            Button("Remove from Trip", role: .destructive) { remove(member, trip: trip) }
        } message: { member in
            Text("\(member.nameForDisplay) will lose access to “\(trip.displayTitle)” right away.")
        }
        .confirmationDialog("Leave “\(trip.displayTitle)”?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Trip", role: .destructive) {
                store.deleteOrLeave(trip)
                dismiss()
                router.popToRoot()
            }
        } message: {
            Text("You'll lose access until someone invites you again.")
        }
    }

    // MARK: - Invite

    @ViewBuilder
    private func inviteSection(_ trip: Trip) -> some View {
        Section {
            Picker("Role", selection: $inviteRole) {
                Text("Can edit").tag(MemberRole.editor)
                Text("View only").tag(MemberRole.viewer)
            }
            .pickerStyle(.segmented)

            if let invite {
                inviteCard(invite, trip: trip)
            } else {
                Button {
                    createInvite(trip)
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                        } else {
                            Label("Create Invite Link", systemImage: "link")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .wfPrimaryButton()
                .disabled(isCreating || !network.isOnline)
            }
            if let inviteError {
                Text(inviteError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        } header: {
            Text("Invite people")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(inviteRole == .editor
                     ? "Editors can add, change and delete plans and invite others."
                     : "Viewers can see everything but can't make changes.")
                if !network.isOnline {
                    Text("Creating an invite needs a connection.")
                }
            }
        }
    }

    private func inviteCard(_ invite: InviteDTO, trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(Self.spacedCode(invite.code))
                .font(.wfInviteCode)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .accessibilityLabel(Text(invite.code).speechSpellsOutCharacters())
            Text("Expires \(expiryText(invite)) · \(inviteRole == .editor ? "Can edit" : "View only")")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            ShareLink(item: shareMessage(invite, trip: trip), subject: Text("Join my trip on Wayfare")) {
                Label("Share Invite…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .wfPrimaryButton()
            Button {
                SystemActions.copy(invite.code)
                toasts.show("Invite code copied", systemImage: "doc.on.doc")
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, Spacing.xs)
    }

    static func spacedCode(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }

    private func expiryText(_ invite: InviteDTO) -> String {
        TimeFormat.date(invite.expiresAt, template: "EEEMMMd", in: .current)
    }

    private func shareMessage(_ invite: InviteDTO, trip: Trip) -> String {
        "Join my trip “\(trip.displayTitle)” on Wayfare: \(invite.url)  (or open Wayfare → + → Join with Code and enter \(invite.code)). Expires \(expiryText(invite)). You'll need the Wayfare app for iPhone."
    }

    private func createInvite(_ trip: Trip) {
        isCreating = true
        inviteError = nil
        Task {
            do {
                invite = try await services.api.createInvite(tripId: trip.id, role: inviteRole)
                successCount += 1
            } catch let error as APIError {
                inviteError = error.isForbidden
                    ? "Only editors and the owner can invite people."
                    : (error.isConnectivity ? "Creating an invite needs a connection." : "Couldn't create an invite. Try again.")
                errorCount += 1
            } catch {
                inviteError = "Couldn't create an invite. Try again."
                errorCount += 1
            }
            isCreating = false
        }
    }

    // MARK: - Members

    private var sortedMembers: [Member] {
        members.sorted {
            ($0.role.sortOrder, $0.nameForDisplay.lowercased()) < ($1.role.sortOrder, $1.nameForDisplay.lowercased())
        }
    }

    private func memberRow(_ member: Member, trip: Trip, myRole: MemberRole) -> some View {
        let isMe = member.userId == session.userId
        let canRemove = myRole == .owner && !isMe && member.role != .owner
        let canLeave = isMe && myRole != .owner
        return HStack(spacing: Spacing.m) {
            AvatarCircle(name: member.nameForDisplay, color: CoverColor.color(forHex: trip.colorHex))
            Text(isMe ? "\(member.nameForDisplay) (You)" : member.nameForDisplay)
                .font(.body)
            Spacer()
            Label(member.role.displayName, systemImage: member.role.symbol)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.nameForDisplay), \(member.role.displayName.lowercased())")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canRemove {
                Button("Remove", role: .destructive) { removing = member }
            } else if canLeave {
                Button("Leave", role: .destructive) { confirmingLeave = true }
            }
        }
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    removing = member
                } label: {
                    Label("Remove from Trip", systemImage: "person.fill.xmark")
                }
            } else if canLeave {
                Button(role: .destructive) {
                    confirmingLeave = true
                } label: {
                    Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private var isConfirmingRemove: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var removeTitle: String {
        "Remove \(removing?.nameForDisplay ?? "")?"
    }

    /// Needs a connection: the server is the only place membership changes.
    private func remove(_ member: Member, trip: Trip) {
        removeError = nil
        let userId = member.userId
        Task {
            do {
                try await services.api.removeMember(tripId: trip.id, userId: userId)
                modelContext.delete(member)
                try? modelContext.save()
                sync.requestSync()
            } catch let error as APIError {
                removeError = error.isConnectivity
                    ? "Removing someone needs a connection."
                    : "Couldn't remove \(member.nameForDisplay). Try again."
                errorCount += 1
            } catch {
                removeError = "Couldn't remove \(member.nameForDisplay). Try again."
                errorCount += 1
            }
        }
    }
}

#Preview {
    ShareTripView(tripId: SampleData.tripId)
        .previewServices()
}
