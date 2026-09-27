import AuthenticationServices
import Foundation

/// Sign in with Apple, the session token, the current user, sign-out and account deletion.
@MainActor
@Observable
final class SessionStore {
    private(set) var user: UserDTO?
    private(set) var isSignedIn: Bool
    /// Apple sent no name and the server has none: ask "What should your travel companions call you?".
    var needsNameCapture = false
    /// A 401 happened: keep local data and ask the user to sign in again (UX spec 5.7).
    var needsReauth = false
    private(set) var isSigningIn = false
    var signInError: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private let defaults: UserDefaults

    /// Wired by AppServices.
    @ObservationIgnored var onSignedIn: (() -> Void)?
    @ObservationIgnored var wipeLocalData: (() -> Void)?
    @ObservationIgnored var apnsTokenProvider: () -> String? = { nil }

    private enum Keys {
        static let user = "session.user"
        static let appleUserId = "session.appleUserId"
    }

    init(api: APIClient, tokens: TokenStore, defaults: UserDefaults = .standard) {
        self.api = api
        self.tokens = tokens
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.user) {
            user = try? JSONDecoder().decode(UserDTO.self, from: data)
        }
        isSignedIn = tokens.token != nil
    }

    /// For previews: a signed-in session without Keychain or network.
    init(previewUser: UserDTO, api: APIClient, tokens: TokenStore) {
        self.api = api
        self.tokens = tokens
        self.defaults = UserDefaults(suiteName: "wayfare.preview") ?? .standard
        user = previewUser
        isSignedIn = true
    }

    var userId: String? { user?.id.lowercased() }

    /// "A trip member" fallback is for others; for yourself we show "You".
    var displayName: String { user?.displayName ?? "" }

    // MARK: - Sign in

    func completeSignIn(_ result: Result<ASAuthorization, Error>) async {
        signInError = nil
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return // Cancelled the Apple sheet: back to idle, no error.
            }
            signInError = "Sign in with Apple didn't complete. Please try again."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                signInError = "Sign in with Apple didn't complete. Please try again."
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = Self.displayName(from: credential.fullName)
            await signIn(identityToken: identityToken, authorizationCode: code, displayName: name,
                         appleUserId: credential.user)
        }
    }

    private func signIn(identityToken: String, authorizationCode: String?, displayName: String?,
                        appleUserId: String) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let response = try await api.signInWithApple(AppleAuthRequest(
                identityToken: identityToken, authorizationCode: authorizationCode, displayName: displayName))
            // A different Apple account on this device: never mix its data with the previous one's.
            if let previous = user?.id, previous.lowercased() != response.user.id.lowercased() {
                wipeLocalData?()
            }
            tokens.save(response.token)
            store(user: response.user)
            defaults.set(appleUserId, forKey: Keys.appleUserId)
            isSignedIn = true
            needsReauth = false
            needsNameCapture = response.user.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            onSignedIn?()
        } catch let error as APIError {
            if error.isConnectivity {
                signInError = "Can't reach Wayfare. Check your connection and try again."
            } else {
                signInError = "Sign in with Apple didn't complete. Please try again."
            }
        } catch {
            signInError = "Sign in with Apple didn't complete. Please try again."
        }
    }

    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let parts = [components.givenName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Profile

    /// `PATCH /v1/me`. Needs a connection.
    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = try await api.updateMe(displayName: trimmed)
        store(user: updated)
        needsNameCapture = false
    }

    func skipNameCapture() {
        needsNameCapture = false
    }

    /// Refreshes the cached user (best effort).
    func refreshMe() async {
        guard isSignedIn else { return }
        do {
            let fresh = try await api.me()
            store(user: fresh)
        } catch {
            // Offline or expired: keep the cached user.
        }
    }

    /// Signs out if the Apple ID credential was revoked in iOS Settings.
    func checkAppleCredentialState() async {
        guard isSignedIn, let appleUserId = defaults.string(forKey: Keys.appleUserId) else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserId)
            if state == .revoked {
                finishSignOut()
            }
        } catch {
            // Unknown state (e.g. offline): keep the session.
        }
    }

    func handleUnauthorized() {
        if isSignedIn {
            needsReauth = true
        }
    }

    // MARK: - Sign out and delete

    /// `POST /v1/auth/logout` (best effort, with the APNs token), then clears everything local.
    func signOut() async {
        try? await api.logout(apnsToken: apnsTokenProvider())
        finishSignOut()
    }

    /// `DELETE /v1/me` must succeed first; only then local data and the Keychain are wiped.
    func deleteAccount() async throws {
        try await api.deleteMe()
        finishSignOut()
    }

    /// Clears the SwiftData store, token, reminders and cached user; returns to Welcome.
    func finishSignOut() {
        wipeLocalData?()
        tokens.clear()
        user = nil
        defaults.removeObject(forKey: Keys.user)
        defaults.removeObject(forKey: Keys.appleUserId)
        isSignedIn = false
        needsNameCapture = false
        needsReauth = false
    }

    private func store(user: UserDTO) {
        self.user = user
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: Keys.user)
        }
    }
}
