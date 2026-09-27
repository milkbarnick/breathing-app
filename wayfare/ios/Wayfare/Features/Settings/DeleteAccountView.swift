import SwiftData
import SwiftUI

/// Delete Account page (UX spec 3.9 item 7; App Store Guideline 5.1.1(v)).
struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(ToastCenter.self) private var toasts

    @Query(filter: #Predicate<Trip> { $0.pendingDelete == false }) private var trips: [Trip]
    @Query private var members: [Member]

    @State private var confirming = false
    @State private var isDeleting = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text("Deleting your account permanently removes: your trips and all their plans, including for anyone you shared them with; and you from trips other people shared with you. Wayfare will also be disconnected from your Apple ID. This can't be undone.")
                    .font(.body)
                    .foregroundStyle(Palette.textPrimary)

                if !ownedSharedTrips.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("These shared trips will be deleted for everyone:")
                            .font(.headline)
                        ForEach(ownedSharedTrips, id: \.trip.id) { entry in
                            Text("\(entry.trip.displayTitle) (\(entry.people) people)")
                                .font(.body)
                        }
                    }
                    .wfCard()
                }

                if let errorText {
                    InlineBanner(systemImage: "exclamationmark.triangle.fill", text: errorText)
                }

                Button {
                    confirming = true
                } label: {
                    if isDeleting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Delete Account").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Palette.danger)
                .disabled(!network.isOnline || isDeleting)

                if !network.isOnline {
                    Text("Deleting your account needs a connection, so the server can remove your data.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Palette.background)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $confirming) {
            Button("Delete", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .sensoryFeedback(.warning, trigger: confirming) { _, new in new }
    }

    private struct OwnedTrip {
        let trip: Trip
        let people: Int
    }

    private var ownedSharedTrips: [OwnedTrip] {
        guard let me = session.userId else { return [] }
        return trips.compactMap { trip in
            guard trip.ownerId == me else { return nil }
            let people = members.filter { $0.tripId == trip.id }.count
            return people > 1 ? OwnedTrip(trip: trip, people: people) : nil
        }
    }

    /// The server call must succeed first; only then local data and the Keychain are wiped.
    private func deleteAccount() {
        isDeleting = true
        errorText = nil
        Task {
            do {
                try await session.deleteAccount()
                toasts.show("Your account has been deleted.")
            } catch let error as APIError where error.isConnectivity {
                errorText = "You're offline. Connect to the internet and try again."
            } catch {
                errorText = "Couldn't delete your account. Please try again."
            }
            isDeleting = false
        }
    }
}
