import Foundation

/// Thin REST transport shared by every CupcakeKit module that talks to the backend.
///
/// Deliberately has no built-in notion of "the current auth scheme" — callers pass whatever
/// `Authorization` header value is right for the call (`Bearer <jwt>` during the one-time login/
/// device-token bootstrap, `DeviceToken <token>` for everything after).
public actor APIClient {
    /// Immutable and `Sendable`, so safe to read without `await` — `AuthService.orcidLoginURL()`
    /// needs this synchronously to build an `ASWebAuthenticationSession` URL.
    public nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    /// GET with no request body.
    public func get<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        authorizationHeader: String? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: .get, query: query, authorizationHeader: authorizationHeader)
        return try await execute(request)
    }

    /// GET a fully-qualified URL as-is — for following a DRF pagination `next` link, which is
    /// always an absolute URL, not a path relative to `baseURL`.
    public func get<Response: Decodable & Sendable>(
        absoluteURL: URL,
        authorizationHeader: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: absoluteURL)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return try await execute(request)
    }

    /// POST/PATCH/PUT with an encodable request body.
    public func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        body: Body,
        query: [URLQueryItem] = [],
        authorizationHeader: String? = nil
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, query: query, authorizationHeader: authorizationHeader)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    public func sendMultipart<Response: Decodable & Sendable>(
        _ path: String,
        body: MultipartFormBuilder,
        authorizationHeader: String? = nil
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: .post, query: [], authorizationHeader: authorizationHeader)
        request.httpBody = body.finalize()
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    /// DELETE (or any call where the server's response body isn't needed).
    public func sendNoContent(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        authorizationHeader: String? = nil
    ) async throws {
        let request = try makeRequest(path: path, method: method, query: query, authorizationHeader: authorizationHeader)
        let (data, response) = try await perform(request)
        try validate(response, body: data)
    }

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        query: [URLQueryItem],
        authorizationHeader: String?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await perform(request)
        try validate(response, body: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, body: data)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }
    }

    private func validate(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: body)
        }
    }
}
