import Foundation

/// An immutable copy of an `Item`. Pure logic (day grouping, reminders, Now/Next) works on
/// snapshots so it can be unit tested without SwiftData.
struct ItemSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var tripId: String
    var kind: ItemKind
    var title: String
    var startAt: Date
    var endAt: Date?
    var startTimeZone: String
    var endTimeZone: String?
    var allDay: Bool = false
    var locationName: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var confirmationCode: String = ""
    var details: [String: String] = [:]
    var notes: String = ""
    var reminderMinutes: Int?
    var sortIndex: Int = 0
    var updatedBy: String?
    var isUnsynced: Bool = false

    var startZone: TimeZone { TimeZone.resolve(startTimeZone) }

    /// `endTimeZone ?? startTimeZone`, per the contract.
    var endZone: TimeZone { TimeZone.resolve(endTimeZone ?? startTimeZone, fallback: startZone) }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    func detail(_ key: String) -> String? {
        guard let value = details[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    var firstNoteLine: String? {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    var transportMode: TransportMode {
        TransportMode(rawValue: detail("mode")?.lowercased() ?? "") ?? .train
    }

    /// The end instant for Now/past logic: `endAt`, or `startAt` when there is no end.
    var effectiveEnd: Date { endAt ?? startAt }
}
