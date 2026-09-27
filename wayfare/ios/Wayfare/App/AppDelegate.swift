import UIKit
import UserNotifications

/// APNs registration, push delivery and notification taps. Owns the app's services.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Created on first access (always on the main thread).
    private(set) lazy var services = AppServices()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Typography.configureNavigationBar()
        UNUserNotificationCenter.current().delegate = self
        _ = services
        return true
    }

    // MARK: - APNs

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        services.devices.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the Simulator and without the Push capability. Local reminders still work.
        print("APNs registration failed: \(error.localizedDescription)")
    }

    /// Delivered while the app runs (or in the background when the push has content-available).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let payload = NotificationPayload(userInfo: userInfo)
        guard payload.isItemChanged else {
            completionHandler(.noData)
            return
        }
        Task {
            await services.handleRemoteNotification(payload)
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground presentation: collaborator pushes are a quiet banner; briefings and reminders play a sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let payload = NotificationPayload(userInfo: notification.request.content.userInfo)
        if payload.isItemChanged {
            completionHandler([.banner, .list])
            Task { @MainActor in
                await self.services.handleRemoteNotification(payload)
            }
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    /// Taps and actions on local reminders and server pushes.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo,
                                          actionIdentifier: response.actionIdentifier)
        Task { @MainActor in
            self.services.handleNotificationResponse(payload)
        }
        completionHandler()
    }
}
