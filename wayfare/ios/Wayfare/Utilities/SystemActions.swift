import Foundation
import MapKit
import UIKit
import UserNotifications

/// The custom keys of a push or local notification, copied out of `userInfo` so they can cross actors.
struct NotificationPayload: Sendable, Equatable {
    var type: String?
    var tripId: String?
    var itemId: String?
    var date: String?
    var actionIdentifier: String = UNNotificationDefaultActionIdentifier

    init(type: String?, tripId: String?, itemId: String?, date: String?,
         actionIdentifier: String = UNNotificationDefaultActionIdentifier) {
        self.type = type
        self.tripId = tripId
        self.itemId = itemId
        self.date = date
        self.actionIdentifier = actionIdentifier
    }

    init(userInfo: [AnyHashable: Any], actionIdentifier: String = UNNotificationDefaultActionIdentifier) {
        type = userInfo["type"] as? String
        tripId = (userInfo["tripId"] as? String)?.lowercased()
        itemId = (userInfo["itemId"] as? String)?.lowercased()
        date = userInfo["date"] as? String
        self.actionIdentifier = actionIdentifier
    }

    var isItemChanged: Bool { type == "itemChanged" }
    var isBriefing: Bool { type == "briefing" }
}

/// Apple Maps, phone calls, links and the pasteboard.
@MainActor
enum SystemActions {
    /// Walking for food/activity, driving otherwise (UX spec 3.4).
    static func directionsMode(for kind: ItemKind) -> String {
        kind == .food || kind == .activity ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
    }

    static func canOpenDirections(_ item: ItemSnapshot) -> Bool {
        item.hasCoordinates || !item.address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Opens Apple Maps with directions. Coordinates win; an address alone is resolved by Maps itself.
    static func openDirections(to item: ItemSnapshot) {
        if let latitude = item.latitude, let longitude = item.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = item.locationName.isEmpty ? item.title : item.locationName
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode(for: item.kind)])
            return
        }
        let address = item.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        var components = URLComponents(string: "https://maps.apple.com/")
        let flag = (item.kind == .food || item.kind == .activity) ? "w" : "d"
        components?.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: flag)]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }

    static func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    static func open(_ link: String) {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        UIApplication.shared.open(url)
    }

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
