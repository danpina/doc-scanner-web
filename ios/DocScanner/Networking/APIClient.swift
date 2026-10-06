import Foundation

/// Thin wrapper around URLSession. Auth is cookie-based (same JWT-in-cookie
/// session the web app uses) — URLSession's shared cookie storage persists and
/// resends it automatically, so there's no token handling to do here.
@MainActor
final class APIClient {
    static let shared = APIClient()
    private init() {}

    enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// Fires whenever a request comes back 401, so the app can drop back to the login screen.
    var onUnauthorized: (() -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // The free Render plan sleeps when idle and takes up to a minute to wake, and saving a
    // multi-page scan uploads a few MB — URLSession's 60s default is too tight for both.
    private let requestTimeout: TimeInterval = 120

    private func makeRequest(
        _ path: String,
        method: Method,
        body: Encodable?,
        accept: String = "application/json"
    ) throws -> URLRequest {
        guard let base = ServerConfig.baseURL else {
            throw APIError(message: "Server URL isn't set.")
        }
        var root = base.absoluteString
        if root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: root + path) else {
            throw APIError(message: "Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = requestTimeout
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    /// Runs the request and turns connectivity failures into messages a person can act on,
    /// instead of surfacing raw URLSession text.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError(message: "You're offline. Check your connection and try again.")
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                throw APIError(message: "Couldn't reach the server. It may be waking up — wait a minute and try again.")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                throw APIError(message: "Couldn't make a secure connection to the server.")
            default:
                throw APIError(message: "Network problem: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func send<Response: Decodable>(
        _ path: String,
        method: Method,
        body: Encodable? = nil
    ) async throws -> Response {
        let request = try makeRequest(path, method: method, body: body)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(message: "The server sent a reply the app couldn't read. Please try again.")
        }
    }

    func sendNoContent(
        _ path: String,
        method: Method,
        body: Encodable? = nil
    ) async throws {
        let request = try makeRequest(path, method: method, body: body)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    /// Raw bytes — used to download a saved PDF.
    func fetchData(_ path: String) async throws -> Data {
        let request = try makeRequest(path, method: .get, body: nil, accept: "application/pdf")
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        return data
    }

    /// These answer 401 for "wrong email/password" or a bad Apple credential — not for an ended session.
    private static let credentialPaths: Set<String> = ["/api/login", "/api/register", "/api/auth/apple"]

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No response from server.")
        }
        let serverMessage = (try? decoder.decode(ServerErrorBody.self, from: data))?.error

        if http.statusCode == 401 {
            if Self.credentialPaths.contains(http.url?.path ?? "") {
                throw APIError(message: serverMessage ?? "Incorrect email or password.")
            }
            onUnauthorized?()
            throw APIError(message: "Your session has ended. Please log in again.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError(message: serverMessage ?? "Request failed (\(http.statusCode)).")
        }
    }
}

private struct ServerErrorBody: Decodable {
    let error: String
}
