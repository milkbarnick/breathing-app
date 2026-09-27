import SwiftUI

/// Standard trip row: 44pt cover, title, "Oct 1 – 9 · Portugal", countdown chip (UX spec 3.1).
struct TripRow: View {
    let trip: Trip
    let role: MemberRole
    let isShared: Bool
    let now: Date

    var body: some View {
        let phase = trip.phase(now: now)
        HStack(spacing: Spacing.m) {
            CoverTile(emoji: trip.coverEmoji, colorHex: trip.colorHex, size: 44)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(trip.displayTitle)
                        .font(.headline)
                        .foregroundStyle(phase == .past ? Palette.textSecondary : Palette.textPrimary)
                        .lineLimit(2)
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if role == .viewer {
                        Image(systemName: "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if trip.needsPush {
                        UnsyncedMarker()
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            if case .upcoming(let days) = phase {
                Pill(text: TimeFormat.countdown(daysUntil: days), style: .countdown)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(phase))
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        let range = TimeFormat.dateRange(trip.startDay, trip.endDay)
        return trip.destination.isEmpty ? range : "\(range) · \(trip.destination)"
    }

    private func accessibilityText(_ phase: TripPhase) -> String {
        var parts = [trip.displayTitle]
        if !trip.destination.isEmpty { parts.append(trip.destination) }
        parts.append(TimeFormat.dateRange(trip.startDay, trip.endDay, includeYear: true))
        if case .upcoming(let days) = phase { parts.append(TimeFormat.countdown(daysUntil: days)) }
        if isShared { parts.append("shared") }
        if role == .viewer { parts.append("view only") }
        if trip.needsPush { parts.append("not yet synced") }
        return parts.joined(separator: ", ")
    }
}

/// Redacted placeholder while the very first sync runs.
struct PlaceholderTripRow: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface2)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Trip title placeholder").font(.headline)
                Text("Oct 1 – 9 · Somewhere").font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// The large card for a trip in progress (design system 9, "Hero card").
struct HeroTripCard: View {
    let trip: Trip
    let items: [ItemSnapshot]
    let now: Date

    var body: some View {
        let phase = trip.phase(now: now)
        let summary = Self.nextUp(items: items, tripZone: trip.tz, now: now)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                CoverTile(emoji: trip.coverEmoji, colorHex: trip.colorHex, size: 64)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(trip.displayTitle)
                            .font(.wfHeroTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        if trip.needsPush { UnsyncedMarker() }
                    }
                    if !trip.destination.isEmpty {
                        Text(trip.destination)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            if case .inProgress(let day, let total) = phase {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Day \(day) of \(total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surface2)
                            Capsule()
                                .fill(CoverColor.color(forHex: trip.colorHex))
                                .frame(width: proxy.size.width * CGFloat(day) / CGFloat(max(total, 1)))
                        }
                    }
                    .frame(height: 4)
                }
            }
            HStack(spacing: Spacing.s) {
                if let kind = summary.kind {
                    Image(systemName: kind.filledSymbol)
                        .foregroundStyle(kind.color)
                }
                Text(summary.text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .wfCard(radius: Radius.headerCard, padding: Spacing.xl)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(phase: phase, summary: summary.text))
        .accessibilityAddTraits(.isButton)
    }

    /// "Next · 20:30 Dinner at Taberna", "Nothing else today", or "Free day".
    static func nextUp(items: [ItemSnapshot], tripZone: TimeZone, now: Date) -> (kind: ItemKind?, text: String) {
        let today = CalendarDay.today(in: tripZone, now: now)
        let todays = items.filter { DayGrouping.groupingDay(for: $0, tripZone: tripZone) == today }
        if todays.isEmpty {
            return (nil, "Free day")
        }
        let next = todays
            .filter { !$0.allDay && $0.kind != .lodging && $0.startAt > now }
            .min { $0.startAt < $1.startAt }
        guard let next else {
            return (nil, "Nothing else today")
        }
        return (next.kind, "Next · \(TimeFormat.time(next.startAt, in: next.startZone)) \(next.title)")
    }

    private func accessibilityText(phase: TripPhase, summary: String) -> String {
        var parts = [trip.displayTitle, trip.destination]
        if case .inProgress(let day, let total) = phase {
            parts.append("Day \(day) of \(total)")
        }
        parts.append(summary.replacingOccurrences(of: "Next · ", with: "Next: "))
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

#Preview("Trip rows") {
    let services = AppServices.preview()
    let trip = SampleData.makeTrip()
    return List {
        HeroTripCard(trip: trip, items: SampleData.makeItems().map(\.snapshot), now: Date())
        TripRow(trip: SampleData.makeUpcomingTrip(), role: .viewer, isShared: true, now: Date())
        PlaceholderTripRow()
    }
    .previewServices(services)
}
