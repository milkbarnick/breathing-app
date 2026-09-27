import SwiftData
import SwiftUI

@main
struct WayfareApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .withServices(appDelegate.services)
        }
    }
}

extension View {
    /// Injects every service into the environment (also used by previews).
    @MainActor
    func withServices(_ services: AppServices) -> some View {
        self
            .environment(services)
            .environment(services.session)
            .environment(services.router)
            .environment(services.sync)
            .environment(services.store)
            .environment(services.permission)
            .environment(services.devices)
            .environment(services.network)
            .environment(services.toasts)
            .modelContainer(services.container)
            .tint(Palette.accent)
    }

    /// For `#Preview`: in-memory services with the sample trip.
    @MainActor
    func previewServices(_ services: AppServices = .preview()) -> some View {
        withServices(services)
    }
}
