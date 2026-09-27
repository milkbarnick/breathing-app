import SwiftUI

/// Pure text helpers for Item Detail.
enum ItemDetailText {
    struct DetailRow: Equatable {
        let key: String
        let label: String
        let value: String
    }

    /// Keys already shown in the header card or the action row, per kind.
    static func headerKeys(for kind: ItemKind) -> Set<String> {
        switch kind {
        case .flight: return ["airline", "flightNumber", "fromCode", "toCode", "terminal", "gate", "seat", "phone", "website", "bookingUrl"]
        case .lodging: return ["roomType", "phone", "website", "bookingUrl"]
        case .transport: return ["mode", "fromName", "toName", "operator", "seat", "phone", "website", "bookingUrl"]
        case .activity, .food: return ["partySize", "phone", "website", "bookingUrl"]
        case .note: return ["phone", "website", "bookingUrl"]
        }
    }

    /// Remaining details as label/value rows. Unknown keys get a title-cased label.
    static func remainingDetails(_ item: ItemSnapshot) -> [DetailRow] {
        let hidden = headerKeys(for: item.kind)
        return item.details
            .filter { !hidden.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.key < $1.key }
            .map { DetailRow(key: $0.key, label: label(forKey: $0.key), value: $0.value) }
    }

    static func label(forKey key: String) -> String {
        switch key {
        case "checkInTime": return "Check-in"
        case "checkOutTime": return "Check-out"
        case "roomType": return "Room type"
        case "partySize": return "Party size"
        case "bookingUrl": return "Booking link"
        case "flightNumber": return "Flight"
        default: return titleCase(key)
        }
    }

    /// "roomType" -> "Room Type", "wifi_password" -> "Wifi Password".
    static func titleCase(_ key: String) -> String {
        var words: [String] = []
        var current = ""
        for character in key {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase && !current.isEmpty {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// "Thu, Oct 1 · 22:30 EDT".
    static func dateTime(_ date: Date, zone: TimeZone, locale: Locale = .current) -> String {
        let day = TimeFormat.date(date, template: "EEEMMMd", in: zone, locale: locale)
        return "\(day) · \(TimeFormat.time(date, in: zone, locale: locale)) \(TimeFormat.zoneAbbreviation(zone, at: date))"
    }

    /// A plain-text summary for pasting into a message (Copy Details).
    static func plainSummary(_ item: ItemSnapshot, locale: Locale = .current) -> String {
        var lines = [item.title]
        if item.allDay {
            lines.append(TimeFormat.date(item.startAt, template: "EEEMMMd", in: item.startZone, locale: locale) + " · All day")
        } else {
            var when = dateTime(item.startAt, zone: item.startZone, locale: locale)
            if let end = item.endAt {
                when += " → " + dateTime(end, zone: item.endZone, locale: locale)
            }
            lines.append(when)
        }
        let location = [item.locationName, item.address].filter { !$0.isEmpty }.joined(separator: ", ")
        if !location.isEmpty { lines.append(location) }
        if !item.confirmationCode.isEmpty { lines.append("Confirmation: \(item.confirmationCode)") }
        return lines.joined(separator: "\n")
    }
}

/// The per-kind header card (UX spec 3.4 "Per-kind header layouts").
struct ItemHeaderCard: View {
    let item: ItemSnapshot
    let tripZone: TimeZone
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.kind == .transport ? item.transportMode.symbol : item.kind.filledSymbol)
                Text(item.kind.displayName)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .font(.wfKindLabel)
            .foregroundStyle(item.kind.color)
            .accessibilityHidden(true)

            switch item.kind {
            case .flight:
                flightHeader
            case .lodging:
                lodgingHeader
            case .transport:
                transportHeader
            case .activity, .food:
                eventHeader
            case .note:
                noteHeader
            }
        }
        .wfCard(radius: Radius.headerCard, padding: Spacing.xl)
    }

    // MARK: Flight

    private var flightHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if let from = item.detail("fromCode"), let to = item.detail("toCode") {
                HStack(alignment: .top) {
                    endpoint(code: from, date: item.startAt, zone: item.startZone, offset: nil, alignment: .leading,
                             label: "Departs")
                    Spacer(minLength: Spacing.s)
                    VStack(spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Rectangle().fill(Palette.separator).frame(height: 1)
                            Image(systemName: "airplane")
                                .foregroundStyle(item.kind.color)
                            Rectangle().fill(Palette.separator).frame(height: 1)
                        }
                        .frame(maxWidth: 80)
                        if let end = item.endAt {
                            Text(TimeFormat.duration(from: item.startAt, to: end))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityLabel("Duration \(TimeFormat.duration(from: item.startAt, to: end))")
                        }
                    }
                    .padding(.top, Spacing.l)
                    Spacer(minLength: Spacing.s)
                    if let end = item.endAt {
                        endpoint(code: to, date: end, zone: item.endZone,
                                 offset: TimeFormat.dayOffsetSuffix(TimeFormat.dayOffset(
                                    start: item.startAt, startZone: item.startZone, end: end, endZone: item.endZone)),
                                 alignment: .trailing, label: "Arrives")
                    } else {
                        Text(to)
                            .font(.wfRouteCode)
                            .kerning(1)
                    }
                }
            } else {
                Text(item.title)
                    .font(.wfDetailTitle)
                timeRange
            }
            let grid = flightGrid
            if !grid.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: Spacing.m) {
                    ForEach(grid, id: \.label) { cell in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(cell.label)
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                            Text(cell.value)
                                .font(.headline.monospacedDigit())
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private struct GridCell {
        let label: String
        let value: String
    }

    private var flightGrid: [GridCell] {
        var cells: [GridCell] = []
        let flight = [item.detail("airline"), item.detail("flightNumber")].compactMap { $0 }.joined(separator: " ")
        if !flight.isEmpty { cells.append(GridCell(label: "Flight", value: flight)) }
        if let terminal = item.detail("terminal") { cells.append(GridCell(label: "Terminal", value: terminal)) }
        if let gate = item.detail("gate") { cells.append(GridCell(label: "Gate", value: gate)) }
        if let seat = item.detail("seat") { cells.append(GridCell(label: "Seat", value: seat)) }
        return cells
    }

    private func endpoint(code: String, date: Date, zone: TimeZone, offset: String?,
                          alignment: HorizontalAlignment, label: String) -> some View {
        VStack(alignment: alignment, spacing: Spacing.xxs) {
            Text(code)
                .font(.wfRouteCode)
                .kerning(1)
                .foregroundStyle(Palette.textPrimary)
            HStack(spacing: 1) {
                Text(TimeFormat.time(date, in: zone))
                    .font(.wfBigTime)
                if let offset {
                    Text(offset)
                        .font(.wfDayOffset)
                        .foregroundStyle(item.kind.color)
                        .baselineOffset(6)
                }
            }
            Text("\(TimeFormat.date(date, template: "EEEMMMd", in: zone)) · \(TimeFormat.zoneAbbreviation(zone, at: date))")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(code), \(TimeFormat.date(date, template: "EEEEMMMMd", in: zone)), \(TimeFormat.time(date, in: zone)) \(TimeFormat.city(forZoneIdentifier: zone.identifier)) time")
    }

    // MARK: Lodging

    private var lodgingHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            titleBlock
            HStack(alignment: .top) {
                stayColumn(label: "Check-in", date: item.startAt, zone: item.startZone, alignment: .leading)
                Spacer()
                if let end = item.endAt {
                    let nights = max(0, CalendarDay(date: item.startAt, in: tripZone).days(to: CalendarDay(date: end, in: tripZone)))
                    Text(nights == 1 ? "1 night" : "\(nights) nights")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, Spacing.l)
                    Spacer()
                    stayColumn(label: "Check-out", date: end, zone: item.endZone, alignment: .trailing)
                }
            }
            if let room = item.detail("roomType") {
                Text(room)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let night = currentNight {
                Text("Night \(night.number) of \(night.total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.kindLodging)
            }
        }
    }

    private func stayColumn(label: String, date: Date, zone: TimeZone, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            Text(TimeFormat.time(date, in: zone))
                .font(.wfBigTime)
            Text(TimeFormat.date(date, template: "EEEMMMd", in: zone))
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Night 2 of 3" while the stay is in progress.
    private var currentNight: (number: Int, total: Int)? {
        guard let end = item.endAt, item.startAt <= now, now < end else { return nil }
        let checkIn = CalendarDay(date: item.startAt, in: tripZone)
        let total = checkIn.days(to: CalendarDay(date: end, in: tripZone))
        let number = checkIn.days(to: CalendarDay.today(in: tripZone, now: now)) + 1
        guard total > 0, (1...total).contains(number) else { return nil }
        return (number, total)
    }

    // MARK: Transport

    private var transportHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let from = item.detail("fromName"), let to = item.detail("toName") {
                Text("\(from) → \(to)")
                    .font(.wfDetailTitle)
                if item.title != "\(from) → \(to)" {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                titleBlock
            }
            HStack(alignment: .top) {
                stayColumn(label: "Departs", date: item.startAt, zone: item.startZone, alignment: .leading)
                Spacer()
                if let end = item.endAt {
                    Text(TimeFormat.duration(from: item.startAt, to: end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, Spacing.l)
                    Spacer()
                    stayColumn(label: "Arrives", date: end, zone: item.endZone, alignment: .trailing)
                }
            }
            HStack(spacing: Spacing.xl) {
                if let op = item.detail("operator") {
                    LabeledStack(label: "Operator", value: op)
                }
                if let seat = item.detail("seat") {
                    LabeledStack(label: "Seat", value: seat)
                }
            }
        }
    }

    // MARK: Activity / Food / Note

    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            titleBlock
            timeRange
            if let party = item.detail("partySize") {
                Text(item.kind == .food ? "Table for \(party)" : "\(party) people")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(item.title)
                .font(.wfDetailTitle)
            timeRange
            if !item.notes.isEmpty {
                Text(item.notes)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(item.title)
                .font(.wfDetailTitle)
                .foregroundStyle(Palette.textPrimary)
            if !item.locationName.isEmpty && item.locationName != item.title {
                Text(item.locationName)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// "Sat, Oct 3 · 20:30–22:30" plus a zone badge when the item zone differs from the trip zone.
    private var timeRange: some View {
        HStack(spacing: Spacing.s) {
            Text(timeRangeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            if !item.allDay, let badge = TimeFormat.zoneBadge(for: item.startAt, itemZone: item.startZone,
                                                             tripZone: tripZone, sectionDay: nil) {
                ZoneBadge(text: badge)
            }
        }
    }

    private var timeRangeText: String {
        let day = TimeFormat.date(item.startAt, template: "EEEMMMd", in: item.startZone)
        if item.allDay { return "\(day) · All day" }
        var text = "\(day) · \(TimeFormat.time(item.startAt, in: item.startZone))"
        if let end = item.endAt {
            text += "–\(TimeFormat.time(end, in: item.endZone))"
            if let suffix = TimeFormat.dayOffsetSuffix(TimeFormat.dayOffset(start: item.startAt, startZone: item.startZone,
                                                                           end: end, endZone: item.endZone)) {
                text += " \(suffix)"
            }
        }
        return text
    }
}

private struct LabeledStack: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(.headline)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.l) {
            ForEach(SampleData.makeItems().map(\.snapshot)) { item in
                ItemHeaderCard(item: item, tripZone: TimeZone.resolve("Europe/Lisbon"))
            }
        }
        .padding()
    }
    .background(Palette.background)
}
