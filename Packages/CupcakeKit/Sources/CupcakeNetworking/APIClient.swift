import Foundation

public actor APIClient {
    public nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var forceOffline = false

    public var isForceOffline: Bool { forceOffline }

    public func setForceOffline(_ value: Bool) {
        forceOffline = value
    }

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

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        authorizationHeader: String? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: .get, query: query, authorizationHeader: authorizationHeader)
        return try await execute(request)
    }

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

    public func fetchAllPages<DTO: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        pageSize: Int = 200,
        authorizationHeader: String,
        onPage: @Sendable ([DTO]) async throws -> Void
    ) async throws {
        var page: PaginatedResponse<DTO> = try await get(
            path,
            query: query + [URLQueryItem(name: "limit", value: String(pageSize))],
            authorizationHeader: authorizationHeader
        )
        while true {
            try await onPage(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await get(absoluteURL: nextURL, authorizationHeader: authorizationHeader)
        }
    }

    public func fetchAllPages<DTO: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        pageSize: Int = 200,
        authorizationHeader: String
    ) async throws -> [DTO] {
        var allResults: [DTO] = []
        var page: PaginatedResponse<DTO> = try await get(
            path,
            query: query + [URLQueryItem(name: "limit", value: String(pageSize))],
            authorizationHeader: authorizationHeader
        )
        while true {
            allResults.append(contentsOf: page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await get(absoluteURL: nextURL, authorizationHeader: authorizationHeader)
        }
        return allResults
    }

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

    public func sendRawJSON<Response: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        json: [String: Any],
        authorizationHeader: String? = nil
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, query: [], authorizationHeader: authorizationHeader)
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
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

    public func downloadData(from url: URL, authorizationHeader: String? = nil) async throws -> (data: Data, suggestedFilename: String?) {
        var secureURL = url
        if secureURL.scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            secureURL = components.url ?? url
        }
        var request = URLRequest(url: secureURL)
        request.httpMethod = HTTPMethod.get.rawValue
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await perform(request)
        try validate(response, body: data)
        let filename = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")
            .flatMap { header -> String? in
                guard let range = header.range(of: "filename=\"") else { return nil }
                let rest = header[range.upperBound...]
                guard let end = rest.firstIndex(of: "\"") else { return nil }
                return String(rest[..<end])
            }
        return (data, filename)
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
        if forceOffline {
            throw APIError.transport(underlying: URLError(.notConnectedToInternet))
        }
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
