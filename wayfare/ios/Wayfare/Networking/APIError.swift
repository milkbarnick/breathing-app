import Foundation

/// Typed errors for every API call. Server errors carry the contract's `code` and `message`.
enum APIError: Error, Equatable, LocalizedError {
    /// No connection (airplane mode, no route to host, dropped connection).
    case offline
    case timedOut
    case cancelled
    /// No session token in the Keychain.
    case notSignedIn
    case invalidURL
    case invalidResponse
    case decoding(String)
    case transport(String)
    /// HTTP 4xx/5xx with the contract's error body (or a synthesized one).
    case server(status: Int, code: String, message: String)

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
             .secureConnectionFailed:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        default:
            self = .transport(urlError.localizedDescription)
        }
    }

    /// Builds a server error from a non-2xx response, reading the contract's error body when present.
    static func from(status: Int, data: Data, decoder: JSONDecoder) -> APIError {
        if let body = try? decoder.decode(APIErrorBody.self, from: data) {
            return .server(status: status, code: body.error.code, message: body.error.message)
        }
        return .server(status: status, code: defaultCode(for: status), message: HTTPURLResponse.localizedString(forStatusCode: status))
    }

    static func defaultCode(for status: Int) -> String {
        switch status {
        case 400: return "bad_request"
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 404: return "not_found"
        case 409: return "conflict"
        case 429: return "rate_limited"
        default: return "internal"
        }
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    /// The contract error code (`unauthorized`, `forbidden`, `not_found`, `bad_request`, `conflict`,
    /// `rate_limited`, `internal`).
    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    /// True for "you're offline" style failures, which never show a modal error.
    var isConnectivity: Bool {
        switch self {
        case .offline, .timedOut: return true
        default: return false
        }
    }

    var isUnauthorized: Bool { status == 401 || code == "unauthorized" }
    var isForbidden: Bool { status == 403 || code == "forbidden" }
    var isNotFound: Bool { status == 404 || code == "not_found" }
    var isRateLimited: Bool { status == 429 || code == "rate_limited" }

    /// The server will never accept this write as-is (so retrying is pointless).
    var isPermanentRejection: Bool {
        guard let status else { return false }
        return status == 400 || status == 403 || status == 404 || status == 409 || status == 422
    }

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline."
        case .timedOut: return "The request timed out."
        case .cancelled: return "Cancelled."
        case .notSignedIn: return "Please sign in again."
        case .invalidURL: return "The server address is invalid."
        case .invalidResponse: return "The server sent an unexpected response."
        case .decoding(let detail): return "The server sent data the app couldn't read. \(detail)"
        case .transport(let detail): return detail
        case .server(_, _, let message): return message
        }
    }
}
