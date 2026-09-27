import Foundation
import UIKit
import UserNotifications

/// The three moments at which we may show our priming card (UX spec 2.4).
enum PrimingMoment: String, Sendable {
    case firstTrip
    case firstReminder
    case joinedTrip
}

/// What the priming sheet shows.
struct PrimingRequest: Identifiable, Equatable {
    let moment: PrimingMoment
    let title: String
    let body: String

    var id: String { moment.rawValue }

    static func firstTrip(tripTitle: String) -> PrimingRequest {
        PrimingRequest(
            moment: .firstTrip,
            title: "Get a heads-up before each plan",
            body: "Wayfare can remind you before flights and check-ins, and send a short morning briefing on each day of \(tripTitle)."
        )
    }

    static func firstReminder(minutes: Int, itemTitle: String) -> PrimingRequest {
        let amount = minutes == 0 ? "at the time of" : "\(TimeFormat.reminderAmount(minutes)) before"
        let title = itemTitle.isEmpty ? "this plan" : itemTitle
        return PrimingRequest(
            moment: .firstReminder,
            title: "Turn on reminders?",
            body: "We'll remind you \(amount) \(title), even with no signal."
        )
    }

    static func joinedTrip(ownerName: String, tripTitle: String) -> PrimingRequest {
        PrimingRequest(
            moment: .joinedTrip,
            title: "Know when plans change",
            body: "Get a notification when \(ownerName) or others add or change plans in \(tripTitle)."
        )
    }
}

/// System notification authorization and the priming bookkeeping. We never ask at launch.
@MainActor
@Observable
final class NotificationPermission {
    private(set) var status: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let enabled: Bool
    private static let shownKey = "notifications.primingShown"

    /// Called after the user grants permission (schedule reminders, register for push).
    @ObservationIgnored var onGranted: (() -> Void)?

    init(defaults: UserDefaults = .standard, enabled: Bool = true) {
        self.defaults = defaults
        self.enabled = enabled
    }

    var isAuthorized: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var isDenied: Bool { status == .denied }
    var isNotDetermined: Bool { status == .notDetermined }

    func refresh() async {
        guard enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    /// Shows the system prompt. Only call this from the priming card.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard enabled else { return false }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        if granted {
            onGranted?()
        }
        return granted
    }

    /// Priming is shown at most once per moment, and never after the system prompt was answered.
    func shouldPrime(_ moment: PrimingMoment) -> Bool {
        status == .notDetermined && !shownMoments.contains(moment.rawValue)
    }

    func markPrimed(_ moment: PrimingMoment) {
        var shown = shownMoments
        shown.insert(moment.rawValue)
        defaults.set(Array(shown), forKey: Self.shownKey)
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var shownMoments: Set<String> {
        Set(defaults.stringArray(forKey: Self.shownKey) ?? [])
    }
}
