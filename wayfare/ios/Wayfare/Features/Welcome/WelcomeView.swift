import AuthenticationServices
import SwiftUI

/// Signed-out root (UX spec 2.1). Also hosts name capture (2.2) and "Please sign in again" (5.7).
struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if session.isSignedIn && session.needsNameCapture && !session.needsReauth {
                NavigationStack {
                    NameCaptureView()
                }
            } else {
                signIn
            }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private var signIn: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Spacer(minLength: Spacing.huge)
                appIcon
                VStack(spacing: Spacing.s) {
                    Text("Wayfare")
                        .font(.wfLargeTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(session.needsReauth ? "Please sign in again to keep syncing." : "Every plan for every trip, in one calm timeline.")
                        .font(.title3)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: Spacing.l) {
                    valueRow("calendar.day.timeline.left", "Flights, stays and plans, sorted by day in local time")
                    valueRow("wifi.slash", "Works offline, syncs when you land")
                    valueRow("person.2.fill", "Plan together with the people you travel with")
                }
                .padding(.top, Spacing.s)

                Spacer(minLength: Spacing.xxl)

                if router.pendingInviteCode != nil {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "envelope.open.fill")
                            .foregroundStyle(Palette.accent)
                        Text("You've been invited to a trip. Sign in to join.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .wfCard()
                    .accessibilityElement(children: .combine)
                }

                if let error = session.signInError {
                    InlineBanner(systemImage: "exclamationmark.triangle.fill", text: error)
                }

                signInButton

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .tint(Palette.accent)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .allowsHitTesting(!session.isSigningIn)
    }

    private var appIcon: some View {
        let size: CGFloat = dynamicTypeSize.isAccessibilitySize ? 64 : 96
        return RoundedRectangle(cornerRadius: size * Radius.appIcon / 96, style: .continuous)
            .fill(LinearGradient(colors: [Color(rgb: 0x0E7F92), Color(rgb: 0x0A6B7C)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Color(rgb: 0xF6F4EF))
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var signInButton: some View {
        if session.isSigningIn {
            ProgressView("Signing in…")
                .frame(maxWidth: .infinity, minHeight: 52)
        } else {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await session.completeSignIn(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
    }

    private var footnote: AttributedString {
        let privacy = AppConfig.privacyPolicyURL?.absoluteString ?? ""
        let terms = AppConfig.termsURL?.absoluteString ?? ""
        let markdown = "By continuing you agree to the [Terms](\(terms)) and [Privacy Policy](\(privacy))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString("By continuing you agree to the Terms and Privacy Policy.")
    }

    private func valueRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "What should your travel companions call you?" (UX spec 2.2).
struct NameCaptureView: View {
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { (1...40).contains(trimmed.count) }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit(save)
            } footer: {
                Text("Shown to people you share trips with, like 'Nick added Dinner at Taberna.'")
            }
            if let errorText {
                Section {
                    InlineBanner(systemImage: "exclamationmark.triangle.fill", text: errorText)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Button(action: save) {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                }
                .wfPrimaryButton()
                .disabled(!isValid || isSaving)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("What should your travel companions call you?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip") { session.skipNameCapture() }
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        errorText = nil
        Task {
            do {
                try await session.updateDisplayName(trimmed)
            } catch let apiError as APIError where apiError.isConnectivity {
                errorText = "You're offline. You can set your name later in Settings."
            } catch {
                errorText = "Couldn't save your name. Try again or skip for now."
            }
            isSaving = false
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .previewServices(AppServices(inMemory: true))
}
