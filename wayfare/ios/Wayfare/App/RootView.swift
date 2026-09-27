import SwiftUI

/// The single NavigationStack (UX spec 1.1), root sheets, the signed-out cover, deep links and lifecycle.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            TripsListView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .trip(let id):
                        TripDetailView(tripId: id)
                    case .item(let id):
                        ItemDetailView(itemId: id)
                    }
                }
        }
        .toastOverlay(toasts)
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
        }
        .fullScreenCover(isPresented: showsWelcome) {
            WelcomeView()
                .toastOverlay(toasts)
        }
        .onOpenURL { url in
            services.handle(url: url)
        }
        .task {
            await services.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.didBecomeActive()
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn {
                services.retryPendingInviteIfNeeded()
            }
        }
        .onChange(of: session.needsNameCapture) { _, needsName in
            if !needsName {
                services.retryPendingInviteIfNeeded()
            }
        }
        .onChange(of: sync.discardNotice) { _, notice in
            if let notice {
                toasts.show(notice, systemImage: "exclamationmark.triangle.fill")
                sync.discardNotice = nil
            }
        }
    }

    /// Welcome is shown while signed out, while capturing the name, and when the session expired.
    private var showsWelcome: Binding<Bool> {
        Binding(
            get: { !session.isSignedIn || session.needsNameCapture || session.needsReauth },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func sheetContent(_ sheet: RootSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .newTrip:
            TripEditorView(trip: nil)
        case .joinWithCode(let prefill):
            JoinWithCodeView(prefill: prefill)
        case .acceptInvite(let code):
            AcceptInviteView(code: code)
        case .priming(let request):
            PrimingSheet(request: request)
        }
    }
}

extension View {
    /// The thin "Offline" bar under the navigation bar, shown 2 s after connectivity is lost.
    @MainActor
    func offlineBanner(_ network: NetworkMonitor) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if network.showsOfflineBanner {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: network.showsOfflineBanner)
    }
}

#Preview {
    RootView()
        .previewServices()
}
