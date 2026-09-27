import SwiftUI

/// Text for one timeline row. Pure, so the view stays simple.
struct TimelineRowText {
    let startTime: String
    let endTime: String?
    let dayOffset: String?
    let zoneBadge: String?
    let subtitle: String?
    let accessibility: String

    init(row: TimelineRow, sectionDay: CalendarDay, tripZone: TimeZone, locale: Locale = .current) {
        let item = row.item
        let instant = row.displayInstant
        let zone = row.displayZone

        var start = "All day"
        var end: String?
        var offset: String?
        var badge: String?
        if !item.allDay {
            start = TimeFormat.time(instant, in: zone, locale: locale)
            if row.role == .single, let endAt = item.endAt {
                end = TimeFormat.time(endAt, in: item.endZone, locale: locale)
                let days = TimeFormat.dayOffset(start: item.startAt, startZone: item.startZone,
                                                end: endAt, endZone: item.endZone)
                offset = TimeFormat.dayOffsetSuffix(days)
            }
            badge = TimeFormat.zoneBadge(for: instant, itemZone: zone, tripZone: tripZone,
                                         sectionDay: sectionDay, locale: locale)
        }
        let sub = Self.subtitle(for: row)

        var parts = [item.kind.displayName, item.title]
        if item.allDay {
            parts.append("All day")
        } else if let end {
            let suffix = offset.map { " (\($0) day)" } ?? ""
            parts.append(start + " to " + end + suffix)
        } else {
            parts.append(start)
        }
        if let badge {
            parts.append(TimeFormat.city(forZoneIdentifier: zone.identifier) + " time, " + badge)
        }
        if let sub { parts.append(sub) }
        if item.reminderMinutes != nil { parts.append("Reminder set") }
        if item.isUnsynced { parts.append("not yet synced") }

        startTime = start
        endTime = end
        dayOffset = offset
        zoneBadge = badge
        subtitle = sub
        accessibility = parts.joined(separator: ". ")
    }

    static func subtitle(for row: TimelineRow) -> String? {
        let item = row.item
        let location = item.locationName.isEmpty ? nil : item.locationName
        switch item.kind {
        case .flight:
            if let from = item.detail("fromCode"), let to = item.detail("toCode") {
                if let seat = item.detail("seat") { return "\(from) → \(to) · Seat \(seat)" }
                return "\(from) → \(to)"
            }
            return location
        case .lodging:
            switch row.role {
            case .checkIn(let nights):
                return nights > 0 ? "Check-in · \(nights == 1 ? "1 night" : "\(nights) nights")" : "Check-in"
            case .checkOut:
                return "Check-out"
            default:
                return location
            }
        case .transport:
            if let from = item.detail("fromName"), let to = item.detail("toName") {
                return "\(from) → \(to)"
            }
            return location
        case .activity, .food:
            return location ?? item.firstNoteLine
        case .note:
            return item.firstNoteLine
        }
    }
}

/// One timeline row: time column, rail + kind chip, title/subtitle, Now/Next pill (UX spec 3.3.1).
struct TimelineRowView: View {
    let row: TimelineRow
    let sectionDay: CalendarDay
    let tripZone: TimeZone
    let now: Date
    let isNow: Bool
    let isNext: Bool
    let isFirstInSection: Bool
    let isLastInSection: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var timeColumnWidth: CGFloat = 64

    private var text: TimelineRowText {
        TimelineRowText(row: row, sectionDay: sectionDay, tripZone: tripZone)
    }

    /// Past items today render muted (not hidden).
    private var isPast: Bool {
        let today = CalendarDay.today(in: tripZone, now: now)
        return sectionDay == today && !isNow && row.item.effectiveEnd < now && !row.item.allDay
    }

    private var symbol: String? {
        row.item.kind == .transport ? row.item.transportMode.symbol : nil
    }

    var body: some View {
        let text = self.text
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    timeColumn(text, alignment: .leading)
                    HStack(alignment: .top, spacing: Spacing.m) {
                        KindIcon(kind: row.item.kind, symbolOverride: symbol)
                        content(text)
                    }
                }
                .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: Spacing.s) {
                    timeColumn(text, alignment: .trailing)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                        .padding(.vertical, 10)
                    rail
                    content(text)
                        .padding(.vertical, 10)
                        .padding(.leading, Spacing.xs)
                }
            }
        }
        .frame(minHeight: 60, alignment: .top)
        .overlay(alignment: .leading) {
            if isNow {
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.s)
                    .offset(x: -Spacing.s)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(text))
        .accessibilityAddTraits(.isButton)
    }

    private func timeColumn(_ text: TimelineRowText, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Spacing.xxs) {
            if row.item.allDay {
                Text(text.startTime)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text(text.startTime)
                    .font(.wfRowTime)
                    .foregroundStyle(isPast ? Palette.textSecondary : Palette.textPrimary)
                if let end = text.endTime {
                    HStack(spacing: 1) {
                        Text(end)
                            .font(.wfRowEndTime)
                            .foregroundStyle(Palette.textSecondary)
                        if let offset = text.dayOffset {
                            Text(offset)
                                .font(.wfDayOffset)
                                .foregroundStyle(row.item.kind.color)
                                .baselineOffset(4)
                        }
                    }
                }
                if let badge = text.zoneBadge {
                    ZoneBadge(text: badge)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirstInSection ? Color.clear : ((isNow || isNext) ? Palette.accent : Palette.separator))
                .frame(width: 2, height: 10)
            KindIcon(kind: row.item.kind, symbolOverride: symbol)
            Rectangle()
                .fill(isLastInSection ? Color.clear : Palette.separator)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
    }

    private func content(_ text: TimelineRowText) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(row.item.title)
                    .font(.wfRowTitle)
                    .foregroundStyle(isPast ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(2)
                if row.item.reminderMinutes != nil {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
                if row.item.isUnsynced {
                    UnsyncedMarker()
                }
                Spacer(minLength: Spacing.xs)
                if isNow {
                    Pill(text: "Now", style: .now)
                } else if isNext {
                    Pill(text: "Next", style: .next)
                }
            }
            if let subtitle = text.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            if isNext {
                Text(TimeFormat.relative(from: now, to: row.item.startAt))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.numericText())
            }
        }
    }

    private func accessibilityLabel(_ text: TimelineRowText) -> String {
        var label = text.accessibility
        if isNow { label += ". Now" }
        if isNext { label += ". Next, \(TimeFormat.relative(from: now, to: row.item.startAt))" }
        return label
    }
}

/// "Staying at Memmo Alfama · Night 2 of 3" band on intermediate lodging days.
struct StayingBand: View {
    let title: String
    let night: Int
    let nights: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.kindLodging)
            Text("Staying at \(title) · Night \(night) of \(nights)")
                .font(.footnote)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: Radius.band, style: .continuous).fill(Palette.kindLodgingTint))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Day section header: "Thu, Oct 1" + "Day 1", Today capsule, Before/After trip in `warning`.
struct TimelineSectionHeader: View {
    let section: TimelineSection
    let isToday: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            switch section.placement {
            case .trip(let dayNumber):
                Text(TimeFormat.dayHeader(section.day))
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text("Day \(dayNumber)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            case .beforeTrip:
                Text("Before trip · \(TimeFormat.dayHeader(section.day))")
                    .font(.headline)
                    .foregroundStyle(Palette.warning)
            case .afterTrip:
                Text("After trip · \(TimeFormat.dayHeader(section.day))")
                    .font(.headline)
                    .foregroundStyle(Palette.warning)
            }
            if isToday {
                Pill(text: "Today", style: .today)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
