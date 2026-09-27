import SwiftUI

/// Info tab: overview, notes, people, summary by kind, actions (UX spec 3.3.3).
struct TripInfoView: View {
    let trip: Trip
    let items: [ItemSnapshot]
    let members: [Member]
    let role: MemberRole
    var onEditTrip: () -> Void
    var onShare: () -> Void
    var onFilter: (ItemKind) -> Void

    @Environment(TripStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var confirmingDelete = false

    private var isOwner: Bool { role == .owner }

    var body: some View {
        List {
            Section("Overview") {
                if !trip.destination.isEmpty {
                    LabeledValueRow(label: "Destination", value: trip.destination)
                }
                LabeledValueRow(
                    label: "Dates",
                    value: "\(TimeFormat.dateRange(trip.startDay, trip.endDay, includeYear: true)) · \(dayCountText)"
                )
                LabeledValueRow(
                    label: "Time zone",
                    value: "\(TimeFormat.city(forZoneIdentifier: trip.timeZone)) · \(TimeFormat.gmtOffset(trip.tz, at: Date()))"
                )
            }
            .listRowBackground(Palette.surface)

            Section("Notes") {
                if trip.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if role.canEdit {
                        Button("Add notes", action: onEditTrip)
                    } else {
                        Text("No notes")
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    Text(trip.notes)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .listRowBackground(Palette.surface)

            Section("People") {
                ForEach(sortedMembers.prefix(5), id: \.key) { member in
                    HStack(spacing: Spacing.m) {
                        AvatarCircle(name: member.nameForDisplay, color: CoverColor.color(forHex: trip.colorHex))
                        Text(member.userId == session.userId ? "\(member.nameForDisplay) (You)" : member.nameForDisplay)
                        Spacer()
                        Label(member.role.displayName, systemImage: member.role.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button("See All & Invite", action: onShare)
            }
            .listRowBackground(Palette.surface)

            if !kindCounts.isEmpty {
                Section("Summary") {
                    ForEach(kindCounts) { entry in
                        Button {
                            onFilter(entry.kind)
                        } label: {
                            HStack(spacing: Spacing.m) {
                                KindIcon(kind: entry.kind)
                                Text(entry.kind.countLabel(entry.count))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .accessibilityHint("Shows only these in the timeline")
                    }
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                if role.canEdit {
                    Button("Edit Trip", action: onEditTrip)
                }
                Button(isOwner ? "Delete Trip" : "Leave Trip", role: .destructive) {
                    confirmingDelete = true
                }
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .confirmationDialog(isOwner ? "Delete “\(trip.displayTitle)”?" : "Leave “\(trip.displayTitle)”?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(isOwner ? "Delete Trip" : "Leave Trip", role: .destructive) {
                store.deleteOrLeave(trip)
                router.popToRoot()
            }
        } message: {
            Text(isOwner
                 ? "This deletes the trip and all \(items.count) plans for everyone it's shared with. This can't be undone."
                 : "You'll lose access until someone invites you again.")
        }
        .sensoryFeedback(.warning, trigger: confirmingDelete) { _, new in new }
    }

    private var dayCountText: String {
        let days = trip.startDay.days(to: trip.endDay) + 1
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var sortedMembers: [Member] {
        members.sorted {
            ($0.role.sortOrder, $0.nameForDisplay.lowercased()) < ($1.role.sortOrder, $1.nameForDisplay.lowercased())
        }
    }

    private var kindCounts: [KindCount] {
        ItemKind.allCases.compactMap { kind in
            let count = items.filter { $0.kind == kind }.count
            return count > 0 ? KindCount(kind: kind, count: count) : nil
        }
    }
}

struct KindCount: Identifiable {
    let kind: ItemKind
    let count: Int

    var id: String { kind.rawValue }
}
