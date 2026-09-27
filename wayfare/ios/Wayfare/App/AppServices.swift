import Foundation
import SwiftData
import UIKit

/// Owns every long-lived object and wires them together. Created once by the AppDelegate
/// (or in memory for previews). Injected into the environment; it has no observed state of its own.
@MainActor
@Observable
final class AppServices {
    let container: ModelContainer
    let tokens: TokenStore
    let api: APIClient
    let scheduler: NotificationScheduler
    let sync: SyncEngine
    let store: TripStore
    let session: SessionStore
    let router: AppRouter
    let permission: NotificationPermission
    let devices: DeviceRegistrar
    let network: NetworkMonitor
    let toasts: ToastCenter

    /// Local AI-import consent flag, per user id (UX spec 3.8, step 0).
    static func aiConsentKey(userId: String?) -> String {
        "ai.importConsent.\(userId ?? "anonymous")"
    }

    init(inMemory: Bool = false, previewUser: UserDTO? = nil) {
        container = Self.makeContainer(inMemory: inMemory)
        let context = container.mainContext

        if let previewUser {
            tokens = TokenStore(inMemoryToken: "preview-token")
            api = APIClient(tokenStore: tokens, baseURLString: { "https://preview.invalid" })
            scheduler = NotificationScheduler(enabled: false)
            permission = NotificationPermission(enabled: false)
            network = NetworkMonitor(startMonitoring: false)
            session = SessionStore(previewUser: previewUser, api: api, tokens: tokens)
        } else {
            tokens = TokenStore()
            api = APIClient(tokenStore: tokens)
            scheduler = NotificationScheduler(enabled: !inMemory)
            permission = NotificationPermission(enabled: !inMemory)
            network = NetworkMonitor(startMonitoring: !inMemory)
            session = SessionStore(api: api, tokens: tokens)
        }
        sync = SyncEngine(context: context, api: api, scheduler: scheduler)
        store = TripStore(context: context, sync: sync)
        router = AppRouter()
        devices = DeviceRegistrar(api: api)
        toasts = ToastCenter()
        wire()
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: Trip.self, Item.self, Member.self, configurations: configuration)
        } catch {
            // A broken store must not brick the app: fall back to memory (sync will refill it).
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: Trip.self, Item.self, Member.self, configurations: memory)
            } catch {
                fatalError("Wayfare could not create its local database: \(error)")
            }
        }
    }

    private func wire() {
        api.onUnauthorized = { [weak self] in
            self?.session.handleUnauthorized()
        }
        scheduler.itemsProvider = { [weak self] in
            self?.store.liveItemSnapshots() ?? []
        }
        sync.currentUserId = { [weak self] in
            self?.session.userId
        }
        store.currentUserId = { [weak self] in
            self?.session.userId
        }
        session.onSignedIn = { [weak self] in
            self?.didSignIn()
        }
        session.wipeLocalData = { [weak self] in
            self?.wipeLocalData()
        }
        session.apnsTokenProvider = { [weak self] in
            self?.devices.apnsToken
        }
        permission.onGranted = { [weak self] in
            guard let self else { return }
            self.scheduler.reschedule()
            self.devices.registerForRemoteNotifications()
            self.devices.scheduleUpload(after: 0)
        }
        network.onReconnect = { [weak self] in
            guard let self, self.session.isSignedIn else { return }
            self.sync.requestSync()
            self.devices.uploadIfNeeded()
            self.retryPendingInviteIfNeeded()
        }
    }

    // MARK: - Lifecycle

    /// First launch work. Never asks for notification permission (UX spec 2.4).
    func start() async {
        scheduler.registerCategories()
        await permission.refresh()
        if permission.isAuthorized {
            devices.registerForRemoteNotifications()
        }
        await session.checkAppleCredentialState()
        guard session.isSignedIn else { return }
        sync.requestSync()
        devices.uploadIfNeeded()
        await session.refreshMe()
    }

    func didBecomeActive() {
        Task {
            await permission.refresh()
            guard session.isSignedIn else { return }
            scheduler.reschedule()
            devices.uploadIfNeeded()
            await sync.syncNow()
        }
    }

    private func didSignIn() {
        sync.requestSync()
        if permission.isAuthorized {
            devices.registerForRemoteNotifications()
        }
        devices.scheduleUpload(after: 0)
        retryPendingInviteIfNeeded()
    }

    /// Wipes SwiftData, reminders, the sync cursor and per-user flags. Used by sign-out and deletion.
    func wipeLocalData() {
        let userId = session.userId
        sync.reset()
        store.wipeAll()
        scheduler.cancelAll()
        devices.resetForSignOut()
        router.reset()
        UserDefaults.standard.removeObject(forKey: Self.aiConsentKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: "tripDetail.lastOpen")
    }

    /// Opens the Accept Invite sheet for a held invite once signed in (UX spec 3.7).
    func retryPendingInviteIfNeeded() {
        guard session.isSignedIn, !session.needsNameCapture, let code = router.pendingInviteCode else { return }
        if case .acceptInvite = router.sheet { return }
        Task {
            // Let a dismissing cover/sheet finish first; SwiftUI drops overlapping presentations.
            try? await Task.sleep(for: .milliseconds(600))
            if router.sheet == nil {
                router.sheet = .acceptInvite(code: code)
            }
        }
    }

    // MARK: - Deep links

    func handle(url: URL) {
        guard let code = AppRouter.inviteCode(from: url) else { return }
        router.setPendingInvite(code)
        if session.isSignedIn && !session.needsReauth && !session.needsNameCapture {
            router.popToRoot()
            router.sheet = .acceptInvite(code: code)
        }
        // Signed out: Welcome shows the invite card; the sheet opens after sign-in.
    }

    // MARK: - Notifications

    /// A tap on a local reminder or a server push (UX spec 4.3).
    func handleNotificationResponse(_ payload: NotificationPayload) {
        guard session.isSignedIn, let tripId = payload.tripId else { return }

        switch payload.actionIdentifier {
        case NotificationScheduler.directionsAction:
            if let itemId = payload.itemId, let item = store.item(id: itemId) {
                SystemActions.openDirections(to: item.snapshot)
            }
            return
        case NotificationScheduler.copyCodeAction:
            if let itemId = payload.itemId, let item = store.item(id: itemId), !item.confirmationCode.isEmpty {
                SystemActions.copy(item.confirmationCode)
                toasts.show("Confirmation code copied", systemImage: "doc.on.doc")
            }
            return
        default:
            break
        }

        if payload.isItemChanged {
            // Show the trip right away from local data, sync, then push the item if it still exists.
            if store.tripExists(tripId) {
                router.show(tripId: tripId)
            }
            router.updatingTripId = tripId
            Task {
                await sync.syncNow()
                router.updatingTripId = nil
                guard store.tripExists(tripId) else {
                    router.popToRoot()
                    toasts.show("You no longer have access to that trip.", systemImage: "exclamationmark.triangle.fill")
                    return
                }
                if let itemId = payload.itemId, store.itemExists(itemId) {
                    router.show(tripId: tripId, itemId: itemId)
                } else {
                    router.show(tripId: tripId)
                    if payload.itemId != nil {
                        toasts.show("That plan was removed.", systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            return
        }

        let open: () -> Void = { [weak self] in
            guard let self else { return }
            if payload.isBriefing {
                self.router.show(tripId: tripId)
                self.router.timelineFocus = TimelineFocus(tripId: tripId, day: payload.date, itemId: nil)
            } else if let itemId = payload.itemId, self.store.itemExists(itemId) {
                self.router.show(tripId: tripId, itemId: itemId)
            } else {
                self.router.show(tripId: tripId)
            }
        }
        if store.tripExists(tripId) {
            open()
        } else {
            Task {
                await sync.syncNow()
                if store.tripExists(tripId) {
                    open()
                } else {
                    router.popToRoot()
                    toasts.show("You no longer have access to that trip.", systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// A push delivered while running: collaborator changes trigger a sync.
    func handleRemoteNotification(_ payload: NotificationPayload) async {
        guard session.isSignedIn, payload.isItemChanged else { return }
        await sync.syncNow()
    }

    // MARK: - Previews

    /// In-memory services with the sample Lisbon & Porto trip.
    static func preview() -> AppServices {
        let services = AppServices(inMemory: true, previewUser: SampleData.user)
        SampleData.insert(into: services.container.mainContext)
        return services
    }
}
