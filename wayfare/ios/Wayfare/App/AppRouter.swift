import Foundation

/// Pushed screens in the single NavigationStack (UX spec 1.1).
enum AppRoute: Hashable {
    case trip(String)
    case item(String)
}

/// Sheets presented from the root.
enum RootSheet: Identifiable, Equatable {
    case settings
    case newTrip
    case joinWithCode(prefill: String?)
    case acceptInvite(code: String)
    case priming(PrimingRequest)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .newTrip: return "newTrip"
        case .joinWithCode: return "joinWithCode"
        case .acceptInvite(let code): return "accept-\(code)"
        case .priming(let request): return "priming-\(request.id)"
        }
    }
}

/// A request for the timeline to scroll to a day or an item (briefing push, new item).
struct TimelineFocus: Equatable {
    let tripId: String
    var day: String?
    var itemId: String?
}

/// Navigation state: the path, root sheets, deep links and pending invites.
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var sheet: RootSheet?
    var timelineFocus: TimelineFocus?
    /// Shows a subtle "Updating…" in the trip's nav bar while a push-triggered sync runs.
    var updatingTripId: String?
    private(set) var pendingInviteCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    private static let pendingInviteKey = "router.pendingInviteCode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pendingInviteCode = defaults.string(forKey: Self.pendingInviteKey)
    }

    // MARK: Deep links

    /// `wayfare://invite/<code>` → the code, or nil for any other URL.
    nonisolated static func inviteCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "wayfare" else { return nil }
        var parts = url.pathComponents.filter { $0 != "/" }
        if let host = url.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        guard parts.count >= 2, parts[0].lowercased() == "invite" else { return nil }
        let code = normalizeCode(parts[1], uppercase: false)
        return code.isEmpty ? nil : code
    }

    /// Removes spaces and hyphens ("AB12-CD34" → "AB12CD34"). Typed codes are also uppercased.
    nonisolated static func normalizeCode(_ text: String, uppercase: Bool = true) -> String {
        let cleaned = text.filter { !$0.isWhitespace && $0 != "-" }
        return uppercase ? cleaned.uppercased() : cleaned
    }

    func setPendingInvite(_ code: String) {
        pendingInviteCode = code
        defaults.set(code, forKey: Self.pendingInviteKey)
    }

    func clearPendingInvite() {
        pendingInviteCode = nil
        defaults.removeObject(forKey: Self.pendingInviteKey)
    }

    // MARK: Navigation

    /// Deep links replace the path: pop to root, push the trip, then the item.
    func show(tripId: String, itemId: String? = nil) {
        sheet = nil
        var newPath: [AppRoute] = [.trip(tripId.lowercased())]
        if let itemId {
            newPath.append(.item(itemId.lowercased()))
        }
        path = newPath
    }

    func popToRoot() {
        path = []
    }

    func reset() {
        path = []
        sheet = nil
        timelineFocus = nil
        updatingTripId = nil
    }
}
