import Foundation
import UIKit

/// Keeps the server's device row (`PUT /v1/devices/current`) in step with the APNs token and the
/// notification preferences in Settings. Preferences are stored locally and sent when online.
@MainActor
@Observable
final class DeviceRegistrar {
    private(set) var apnsToken: String?
    private(set) var briefingEnabled: Bool
    private(set) var briefingHour: Int
    private(set) var collabAlertsEnabled: Bool

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    private enum Keys {
        static let token = "device.apnsToken"
        static let briefingEnabled = "device.briefingEnabled"
        static let briefingHour = "device.briefingHour"
        static let collabAlerts = "device.collabAlertsEnabled"
        static let needsUpload = "device.needsUpload"
    }

    /// Hours offered in Settings (5 AM to 11 AM). The contract accepts 0–23.
    static let briefingHours = Array(5...11)

    init(api: APIClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        apnsToken = defaults.string(forKey: Keys.token)
        briefingEnabled = (defaults.object(forKey: Keys.briefingEnabled) as? Bool) ?? true
        briefingHour = (defaults.object(forKey: Keys.briefingHour) as? Int) ?? 7
        collabAlertsEnabled = (defaults.object(forKey: Keys.collabAlerts) as? Bool) ?? true
    }

    /// Lowercase hex of the APNs device token.
    static func hexString(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    /// Asks iOS for an APNs token. Only call once notifications are authorized.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        let hex = Self.hexString(from: deviceToken)
        let changed = hex != apnsToken
        apnsToken = hex
        defaults.set(hex, forKey: Keys.token)
        if changed || defaults.bool(forKey: Keys.needsUpload) {
            scheduleUpload(after: 0)
        }
    }

    func setBriefingEnabled(_ value: Bool) {
        briefingEnabled = value
        defaults.set(value, forKey: Keys.briefingEnabled)
        scheduleUpload()
    }

    func setBriefingHour(_ value: Int) {
        briefingHour = min(23, max(0, value))
        defaults.set(briefingHour, forKey: Keys.briefingHour)
        scheduleUpload()
    }

    func setCollabAlertsEnabled(_ value: Bool) {
        collabAlertsEnabled = value
        defaults.set(value, forKey: Keys.collabAlerts)
        scheduleUpload()
    }

    /// Resends when an earlier upload failed (e.g. offline), or when the device zone changed.
    func uploadIfNeeded() {
        if defaults.bool(forKey: Keys.needsUpload) || defaults.string(forKey: "device.lastZone") != TimeZone.current.identifier {
            scheduleUpload(after: 0)
        }
    }

    /// Debounced by 1 s, per the UX spec.
    func scheduleUpload(after delay: Double = 1) {
        defaults.set(true, forKey: Keys.needsUpload)
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.upload()
        }
    }

    private func upload() async {
        guard let apnsToken, api.hasToken else { return }
        let registration = DeviceRegistrationDTO(
            apnsToken: apnsToken,
            environment: AppConfig.apnsEnvironment,
            timeZone: TimeZone.current.identifier,
            briefingEnabled: briefingEnabled,
            briefingHour: briefingHour,
            collabAlertsEnabled: collabAlertsEnabled
        )
        do {
            try await api.registerDevice(registration)
            defaults.set(false, forKey: Keys.needsUpload)
            defaults.set(TimeZone.current.identifier, forKey: "device.lastZone")
        } catch {
            // Stays flagged; retried on reconnect, foreground, or the next change.
        }
    }

    /// Sign-out: forget preferences sync state (the token itself stays valid for this device).
    func resetForSignOut() {
        uploadTask?.cancel()
        defaults.set(true, forKey: Keys.needsUpload)
        defaults.removeObject(forKey: "device.lastZone")
        defaults.removeObject(forKey: Keys.briefingEnabled)
        defaults.removeObject(forKey: Keys.briefingHour)
        defaults.removeObject(forKey: Keys.collabAlerts)
        briefingEnabled = true
        briefingHour = 7
        collabAlertsEnabled = true
    }
}
