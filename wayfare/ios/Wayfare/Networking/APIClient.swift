import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// The Wayfare API (docs/api-contract.md). Main-actor isolated for simplicity: URLSession does the
/// waiting off the main thread, and payloads are small.
@MainActor
final class APIClient {
    private let session: URLSession
    private let tokenStore: TokenStore
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()
    private let baseURLString: () -> String

    /// Called on any 401 from an authenticated endpoint (expired or revoked session).
    var onUnauthorized: (() -> Void)?

    init(tokenStore: TokenStore,
         session: URLSession = .shared,
         baseURLString: @escaping () -> String = { AppConfig.apiBaseURLString }) {
        self.tokenStore = tokenStore
        self.session = session
        self.baseURLString = baseURLString
    }

    var hasToken: Bool { tokenStore.token != nil }

    // MARK: - Health and auth

    func health(baseURLOverride: String? = nil) async throws -> HealthDTO {
        let data = try await perform(.get, "/v1/health", body: nil, auth: false, baseOverride: baseURLOverride)
        return try decode(HealthDTO.self, from: data)
    }

    func signInWithApple(_ request: AppleAuthRequest) async throws -> AuthResponseDTO {
        try await send(.post, "/v1/auth/apple", body: request, auth: false)
    }

    func me() async throws -> UserDTO {
        try await get("/v1/me")
    }

    func updateMe(displayName: String) async throws -> UserDTO {
        try await send(.patch, "/v1/me", body: UpdateMeRequest(displayName: displayName))
    }

    /// `DELETE /v1/me` → 204.
    func deleteMe() async throws {
        _ = try await perform(.delete, "/v1/me", body: nil, auth: true)
    }

    /// `POST /v1/auth/logout` → 204. Sends the APNs token so the server unregisters this device.
    func logout(apnsToken: String?) async throws {
        var body: Data?
        if let apnsToken, !apnsToken.isEmpty {
            body = try encode(LogoutRequest(apnsToken: apnsToken))
        }
        _ = try await perform(.post, "/v1/auth/logout", body: body, auth: true)
    }

    // MARK: - Devices

    func registerDevice(_ registration: DeviceRegistrationDTO) async throws {
        let _: OkDTO = try await send(.put, "/v1/devices/current", body: registration)
    }

    // MARK: - Sync

    func sync(since cursor: Int) async throws -> SyncResponseDTO {
        try await get("/v1/sync", query: [URLQueryItem(name: "since", value: String(max(0, cursor)))])
    }

    // MARK: - Trips

    func putTrip(id: String, _ trip: TripWriteDTO) async throws -> TripDTO {
        try await send(.put, "/v1/trips/\(pathSafe(id))", body: trip)
    }

    func deleteTrip(id: String) async throws {
        _ = try await perform(.delete, "/v1/trips/\(pathSafe(id))", body: nil, auth: true)
    }

    // MARK: - Items

    func putItem(_ item: ItemWriteDTO) async throws -> ItemDTO {
        try await send(.put, "/v1/trips/\(pathSafe(item.tripId))/items/\(pathSafe(item.id))", body: item)
    }

    func deleteItem(tripId: String, itemId: String) async throws {
        _ = try await perform(.delete, "/v1/trips/\(pathSafe(tripId))/items/\(pathSafe(itemId))",
                              body: nil, auth: true)
    }

    // MARK: - Sharing

    func createInvite(tripId: String, role: MemberRole) async throws -> InviteDTO {
        try await send(.post, "/v1/trips/\(pathSafe(tripId))/invites", body: CreateInviteRequest(role: role.rawValue))
    }

    func acceptInvite(code: String) async throws -> TripDTO {
        let data = try await perform(.post, "/v1/invites/\(pathSafe(code))/accept", body: nil, auth: true)
        return try decode(TripDTO.self, from: data)
    }

    func removeMember(tripId: String, userId: String) async throws {
        _ = try await perform(.delete, "/v1/trips/\(pathSafe(tripId))/members/\(pathSafe(userId))",
                              body: nil, auth: true)
    }

    // MARK: - AI import

    /// Drafts only; nothing is saved on the server. 100 s timeout: longer than the server's 90 s Anthropic call, so the app never gives up on an import the server is still finishing (and counting).
    func importDrafts(tripId: String, text: String) async throws -> [ItemDraftDTO] {
        let response: ImportResponseDTO = try await send(
            .post, "/v1/trips/\(pathSafe(tripId))/import", body: ImportRequest(text: text), timeout: 100)
        return response.items
    }

    // MARK: - Core

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await perform(.get, path, query: query, body: nil, auth: true)
        return try decode(T.self, from: data)
    }

    private func send<Body: Encodable, T: Decodable>(_ method: HTTPMethod, _ path: String, body: Body,
                                                     auth: Bool = true, timeout: TimeInterval = 30) async throws -> T {
        let data = try await perform(method, path, body: try encode(body), auth: auth, timeout: timeout)
        return try decode(T.self, from: data)
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try encoder.encode(body)
        } catch {
            throw APIError.decoding("Couldn't encode the request.")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func perform(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: Data?,
                         auth: Bool, timeout: TimeInterval = 30, baseOverride: String? = nil) async throws -> Data {
        let base = baseOverride ?? baseURLString()
        guard var components = URLComponents(string: base + path) else { throw APIError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth {
            guard let token = tokenStore.token else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError(urlError: error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = APIError.from(status: http.statusCode, data: data, decoder: decoder)
            if http.statusCode == 401 && auth {
                onUnauthorized?()
            }
            throw error
        }
        return data
    }

    /// Path segments are UUIDs or invite codes; percent-encode anyway so user input can't change the path.
    private func pathSafe(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? segment
    }
}
