import Foundation
import SwiftData

/// A trip member row from `/v1/sync`. Members are read-only on the device.
@Model
final class Member {
    /// "<tripId>|<userId>", both lowercase.
    @Attribute(.unique) var key: String
    var tripId: String
    var userId: String
    var displayName: String
    var roleRaw: String
    var updatedAt: Int

    init(tripId: String, userId: String, displayName: String, role: MemberRole, updatedAt: Int) {
        self.key = Member.key(tripId: tripId, userId: userId)
        self.tripId = tripId.lowercased()
        self.userId = userId.lowercased()
        self.displayName = displayName
        self.roleRaw = role.rawValue
        self.updatedAt = updatedAt
    }

    static func key(tripId: String, userId: String) -> String {
        "\(tripId.lowercased())|\(userId.lowercased())"
    }
}

extension Member {
    var role: MemberRole { MemberRole(rawValue: roleRaw) ?? .viewer }

    /// "A trip member" when the person never set a name (UX spec 2.2).
    var nameForDisplay: String {
        displayName.trimmingCharacters(in: .whitespaces).isEmpty ? "A trip member" : displayName
    }
}
