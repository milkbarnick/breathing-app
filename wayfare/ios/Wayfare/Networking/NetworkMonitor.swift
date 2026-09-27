import Foundation
import Network

/// Connectivity for the offline banner and for "needs a connection" states.
/// The banner appears only after 2 s offline, so brief drops don't flicker it (UX spec 3).
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private(set) var showsOfflineBanner = false

    /// Called when connectivity comes back (used to kick a sync).
    @ObservationIgnored var onReconnect: (() -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    init(startMonitoring: Bool = true) {
        guard startMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.apply(online: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.wayfare.network-monitor"))
    }

    private func apply(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        bannerTask?.cancel()
        if online {
            showsOfflineBanner = false
            onReconnect?()
        } else {
            bannerTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                if self?.isOnline == false {
                    self?.showsOfflineBanner = true
                }
            }
        }
    }
}
