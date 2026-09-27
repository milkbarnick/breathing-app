import SwiftUI

/// Day-by-day timeline for a trip (UX spec 3.3.1). Named `TripTimelineView` to avoid clashing with
/// SwiftUI's `TimelineView`, which it uses to refresh Now/Next every minute.
struct TripTimelineView: View {
    let trip: Trip
    let items: [ItemSnapshot]
    let canEdit: Bool
    let isShared: Bool
    var kindFilter: ItemKind?
    var onClearFilter: () -> Void = {}
    var onAdd: (ItemKind?, CalendarDay) -> Void
    var onImport: () -> Void
    var onEdit: (String) -> Void
    var onDelete: (String) -> Void
    var onDuplicate: (String) -> Void

    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var didInitialScroll = false
    @State private var todayAnchorVisible = true
    @State private var confirmingDelete: ItemSnapshot?
    @State private var copyCount = 0

    private var visibleItems: [ItemSnapshot] {
        guard let kindFilter else { return items }
        return items.filter { $0.kind == kindFilter }
    }

    var body: some View {
        if items.isEmpty {
            emptyTrip
        } else {
            SwiftUI.TimelineView(.everyMinute) { context in
                timeline(now: context.date)
            }
            .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible,
                                presenting: confirmingDelete) { item in
                Button("Delete", role: .destructive) { onDelete(item.id) }
            } message: { _ in
                if isShared {
                    Text("It will be removed for everyone on this trip.")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: copyCount)
        }
    }

    // MARK: - Timeline

    private func timeline(now: Date) -> some View {
        let zone = trip.tz
        let sections = DayGrouping.sections(items: visibleItems, tripStart: trip.startDay,
                                            tripEnd: trip.endDay, tripZone: zone)
        let phase = trip.phase(now: now)
        let noHighlight: (now: Set<String>, next: String?) = (now: [], next: nil)
        let highlight = phase.highlightsNowNext ? NowNext.compute(items: visibleItems, now: now) : noHighlight
        let today = CalendarDay.today(in: zone, now: now)
        let todaySection = sections.first { $0.day == today }
        let todayAnchor = todaySection.map { anchorId(for: $0) }

        return ScrollViewReader { proxy in
            List {
                if let kindFilter {
                    filterChip(kindFilter)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Palette.background)
                }
                ForEach(sections) { section in
                    Section {
                        sectionRows(section, now: now, highlight: highlight, todayAnchor: todayAnchor)
                    } header: {
                        TimelineSectionHeader(section: section, isToday: section.day == today)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .refreshable { await sync.syncNow() }
            .overlay(alignment: .bottom) {
                if let todayAnchor, !todayAnchorVisible {
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                            proxy.scrollTo(todayAnchor, anchor: .top)
                        }
                    } label: {
                        Label("Today", systemImage: "arrow.up")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .background(Capsule().fill(Palette.surface))
                    .padding(.bottom, Spacing.l)
                }
            }
            .onAppear {
                guard !didInitialScroll else { return }
                didInitialScroll = true
                if let focus = router.timelineFocus, focus.tripId == trip.id {
                    scroll(to: focus, sections: sections, proxy: proxy)
                } else if phase.isInProgress, let todayAnchor {
                    proxy.scrollTo(todayAnchor, anchor: .top)
                }
            }
            .onChange(of: router.timelineFocus) { _, focus in
                guard let focus, focus.tripId == trip.id else { return }
                scroll(to: focus, sections: sections, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func sectionRows(_ section: TimelineSection, now: Date,
                             highlight: (now: Set<String>, next: String?), todayAnchor: String?) -> some View {
        if section.rows.isEmpty {
            emptyDayRow(section)
                .id(anchorId(for: section))
                .onAppear { if anchorId(for: section) == todayAnchor { todayAnchorVisible = true } }
                .onDisappear { if anchorId(for: section) == todayAnchor { todayAnchorVisible = false } }
        } else {
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, section: section, index: index, now: now, highlight: highlight)
                    .onAppear { if row.id == todayAnchor { todayAnchorVisible = true } }
                    .onDisappear { if row.id == todayAnchor { todayAnchorVisible = false } }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TimelineRow, section: TimelineSection, index: Int, now: Date,
                         highlight: (now: Set<String>, next: String?)) -> some View {
        let item = row.item
        Button {
            router.path.append(.item(item.id))
        } label: {
            if case .staying(let night, let nights) = row.role {
                StayingBand(title: item.title, night: night, nights: nights)
                    .padding(.vertical, Spacing.xs)
            } else {
                TimelineRowView(
                    row: row, sectionDay: section.day, tripZone: trip.tz, now: now,
                    isNow: highlight.now.contains(item.id) && row.role == .single,
                    isNext: highlight.next == item.id && row.role == .single,
                    isFirstInSection: index == 0 || section.rows[index - 1].isBand,
                    isLastInSection: index == section.rows.count - 1
                )
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Palette.background)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l, bottom: 0, trailing: Spacing.l))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button(role: .destructive) {
                    confirmingDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canEdit {
                Button {
                    onEdit(item.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Palette.accent)
            }
        }
        .contextMenu {
            contextMenuItems(item)
        }
        .accessibilityActions {
            contextMenuItems(item)
        }
    }

    @ViewBuilder
    private func contextMenuItems(_ item: ItemSnapshot) -> some View {
        if canEdit {
            Button {
                onEdit(item.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                onDuplicate(item.id)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        if !item.confirmationCode.isEmpty {
            Button {
                SystemActions.copy(item.confirmationCode)
                copyCount += 1
                toasts.show("Confirmation code copied", systemImage: "doc.on.doc")
            } label: {
                Label("Copy Confirmation Code", systemImage: "doc.on.doc")
            }
        }
        if item.hasCoordinates {
            Button {
                SystemActions.openDirections(to: item)
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
        }
        if canEdit {
            Button(role: .destructive) {
                confirmingDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func emptyDayRow(_ section: TimelineSection) -> some View {
        HStack {
            Text("Nothing planned")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if canEdit {
                Button {
                    onAdd(nil, section.day)
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, Spacing.m)
        .listRowSeparator(.hidden)
        .listRowBackground(Palette.background)
    }

    private func filterChip(_ kind: ItemKind) -> some View {
        HStack {
            Button {
                onClearFilter()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: kind.filledSymbol)
                    Text(kind.displayName + "s")
                    Image(systemName: "xmark")
                }
                .font(.subheadline.bold())
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(Capsule().fill(Palette.accentTint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Showing \(kind.displayName) only. Clear filter")
            Spacer()
        }
    }

    // MARK: - Empty trip

    private var emptyTrip: some View {
        ContentUnavailableView {
            Label {
                Text(canEdit ? "Start your plan" : "Nothing planned yet")
            } icon: {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(Palette.accent)
            }
        } description: {
            if canEdit {
                Text("Add your flights, where you're staying, and anything you've booked.")
            }
        } actions: {
            if canEdit {
                Button("Add Item") { onAdd(nil, trip.startDay) }
                    .buttonStyle(.borderedProminent)
                Button {
                    onImport()
                } label: {
                    Label("Import from Email", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
        .background(Palette.background)
    }

    // MARK: - Helpers

    private func anchorId(for section: TimelineSection) -> String {
        section.rows.first?.id ?? "empty-\(section.id)"
    }

    private func scroll(to focus: TimelineFocus, sections: [TimelineSection], proxy: ScrollViewProxy) {
        if let itemId = focus.itemId, let row = sections.flatMap(\.rows).first(where: { $0.item.id == itemId && !$0.isBand }) {
            proxy.scrollTo(row.id, anchor: .center)
        } else if let day = focus.day, let section = sections.first(where: { $0.day.string == day }) {
            proxy.scrollTo(anchorId(for: section), anchor: .top)
        }
        router.timelineFocus = nil
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
    }

    private var deleteTitle: String {
        "Delete “\(confirmingDelete?.title ?? "")”?"
    }
}
