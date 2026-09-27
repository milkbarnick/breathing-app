import SwiftUI

/// The six item kinds from the contract (`Item.kind`).
enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case flight
    case lodging
    case activity
    case food
    case transport
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight: return "Flight"
        case .lodging: return "Lodging"
        case .activity: return "Activity"
        case .food: return "Food"
        case .transport: return "Transport"
        case .note: return "Note"
        }
    }

    /// Outline symbol (design system 4.1).
    var symbol: String {
        switch self {
        case .flight: return "airplane"
        case .lodging: return "bed.double"
        case .activity: return "ticket"
        case .food: return "fork.knife"
        case .transport: return "tram"
        case .note: return "note.text"
        }
    }

    /// Filled symbol used in chips and pins.
    var filledSymbol: String {
        switch self {
        case .flight: return "airplane"
        case .lodging: return "bed.double.fill"
        case .activity: return "ticket.fill"
        case .food: return "fork.knife"
        case .transport: return "tram.fill"
        case .note: return "note.text"
        }
    }

    /// Foreground color token (`kindFlight`, ...).
    var color: Color {
        switch self {
        case .flight: return Palette.kindFlight
        case .lodging: return Palette.kindLodging
        case .activity: return Palette.kindActivity
        case .food: return Palette.kindFood
        case .transport: return Palette.kindTransport
        case .note: return Palette.kindNote
        }
    }

    /// Tint token (`kindFlightTint`, ...) for chip and band backgrounds.
    var tint: Color {
        switch self {
        case .flight: return Palette.kindFlightTint
        case .lodging: return Palette.kindLodgingTint
        case .activity: return Palette.kindActivityTint
        case .food: return Palette.kindFoodTint
        case .transport: return Palette.kindTransportTint
        case .note: return Palette.kindNoteTint
        }
    }

    /// Map pins always use the light kind hex so white symbols stay legible (design system 2.2).
    var pinColor: Color {
        switch self {
        case .flight: return Color(rgb: 0x1E5FCC)
        case .lodging: return Color(rgb: 0x7045B8)
        case .activity: return Color(rgb: 0x0D7550)
        case .food: return Color(rgb: 0xB8431A)
        case .transport: return Color(rgb: 0x935400)
        case .note: return Color(rgb: 0x5C6675)
        }
    }

    /// Plural label for the trip summary ("2 flights").
    func countLabel(_ count: Int) -> String {
        switch self {
        case .flight: return count == 1 ? "1 flight" : "\(count) flights"
        case .lodging: return count == 1 ? "1 stay" : "\(count) stays"
        case .activity: return count == 1 ? "1 activity" : "\(count) activities"
        case .food: return count == 1 ? "1 meal" : "\(count) meals"
        case .transport: return count == 1 ? "1 journey" : "\(count) journeys"
        case .note: return count == 1 ? "1 note" : "\(count) notes"
        }
    }

    /// Start / end labels in the item form and detail.
    var startLabel: String {
        switch self {
        case .flight, .transport: return "Departs"
        case .lodging: return "Check-in"
        default: return "Starts"
        }
    }

    var endLabel: String {
        switch self {
        case .flight, .transport: return "Arrives"
        case .lodging: return "Check-out"
        default: return "Ends"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .flight: return "e.g. TP 202 to Lisbon"
        case .lodging: return "e.g. Memmo Alfama"
        case .activity: return "e.g. Tram 28 tour"
        case .food: return "e.g. Dinner at Taberna"
        case .transport: return "e.g. Train to Porto"
        case .note: return "e.g. Pick up SIM card"
        }
    }

    /// Default reminder on Add (UX spec 3.5).
    var defaultReminderMinutes: Int? {
        switch self {
        case .flight: return 180
        case .transport, .activity, .food: return 60
        case .lodging, .note: return nil
        }
    }
}

/// Transport modes stored in `details.mode`.
enum TransportMode: String, CaseIterable, Identifiable, Sendable {
    case train, bus, car, ferry, rideshare, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .train: return "Train"
        case .bus: return "Bus"
        case .car: return "Car"
        case .ferry: return "Ferry"
        case .rideshare: return "Rideshare"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .train: return "tram.fill"
        case .bus: return "bus.fill"
        case .car: return "car.fill"
        case .ferry: return "ferry.fill"
        case .rideshare: return "car.side.fill"
        case .other: return "arrow.left.arrow.right"
        }
    }
}

/// Member roles from the contract.
enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner, editor, viewer

    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }

    var symbol: String {
        switch self {
        case .owner: return "crown.fill"
        case .editor: return "pencil"
        case .viewer: return "eye"
        }
    }

    var canEdit: Bool { self != .viewer }

    var sortOrder: Int {
        switch self {
        case .owner: return 0
        case .editor: return 1
        case .viewer: return 2
        }
    }
}
