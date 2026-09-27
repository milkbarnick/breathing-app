import Foundation

/// One AI draft in the review list.
struct DraftRow: Identifiable, Equatable {
    let id: UUID
    var form: ItemFormState
    var included: Bool
    var warnings: [String]

    var hasWarnings: Bool { !warnings.isEmpty }
}

/// Pure helpers for AI import review (UX spec 3.8, step 3). Unit-testable.
enum ImportReview {
    static let maxCharacters = 20_000

    /// Builds review rows: forms with trip-zone fallbacks, heuristic warnings, duplicates unchecked.
    static func rows(from drafts: [ItemDraftDTO], trip: TripContext, existing: [ItemSnapshot]) -> [DraftRow] {
        drafts.map { draft in
            let form = ItemFormState(draft: draft, tripZone: trip.timeZone, fallbackDay: trip.start)
            let duplicate = duplicateTitle(of: form, in: existing)
            var warnings = warningsFor(draft: draft, form: form, trip: trip)
            if let duplicate {
                warnings.append("Possible duplicate of “\(duplicate)”")
            }
            return DraftRow(id: form.id, form: form, included: duplicate == nil, warnings: warnings)
        }
    }

    /// The trip facts the warnings need (a value type, so tests don't need SwiftData).
    struct TripContext {
        let start: CalendarDay
        let end: CalendarDay
        let timeZone: String

        var zone: TimeZone { TimeZone.resolve(timeZone) }
    }

    static func warningsFor(draft: ItemDraftDTO, form: ItemFormState, trip: TripContext) -> [String] {
        var warnings: [String] = []
        let day = form.allDay ? CalendarDay(date: form.startAt, in: form.startZone) : CalendarDay(date: form.startAt, in: trip.zone)
        if day < trip.start || day > trip.end {
            warnings.append("Outside trip dates (\(TimeFormat.shortDay(day)))")
        }
        if draft.startTimeZone.flatMap({ TimeZone(identifier: $0) }) == nil || draft.startAt == nil {
            warnings.append("Check the time zone")
        }
        if form.kind == .lodging && form.endAt == nil {
            warnings.append("Check-out missing")
        }
        if form.kind == .flight && form.endAt == nil {
            warnings.append("Arrival time missing")
        }
        return warnings
    }

    /// Same kind and confirmation code, or same kind, start within 5 minutes and a matching title prefix.
    static func duplicateTitle(of form: ItemFormState, in existing: [ItemSnapshot]) -> String? {
        let code = form.confirmationCode.trimmingCharacters(in: .whitespaces).lowercased()
        let prefix = String(form.effectiveTitle.lowercased().prefix(6))
        for item in existing where item.kind == form.kind {
            if !code.isEmpty && item.confirmationCode.lowercased() == code {
                return item.title
            }
            let closeInTime = abs(item.startAt.timeIntervalSince(form.startAt)) <= 5 * 60
            if closeInTime && !prefix.isEmpty && item.title.lowercased().hasPrefix(prefix) {
                return item.title
            }
        }
        return nil
    }

    /// "Thu, Oct 1 · 22:30 EDT → Fri, Oct 2 · 09:45 WEST". Zones are always shown on drafts.
    static func whenText(_ form: ItemFormState, locale: Locale = .current) -> String {
        if form.allDay {
            return TimeFormat.date(form.startAt, template: "EEEMMMd", in: form.startZone, locale: locale) + " · All day"
        }
        var text = ItemDetailText.dateTime(form.startAt, zone: form.startZone, locale: locale)
        if let end = form.endAt {
            text += " → " + ItemDetailText.dateTime(end, zone: form.endZone, locale: locale)
        }
        return text
    }
}
