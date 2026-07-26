import Foundation
import Testing

@testable import CupcakeNetworking

private struct Widget: Decodable, Sendable {
    let displayName: String
}

@Suite("APIClient", .serialized)
struct APIClientTests {
    @Test("decodes a paginated envelope with snake_case results")
    func decodesPaginatedEnvelope() async throws {
        StubURLProtocol.handler = { request in
            let json = Data(#"{"count": 1, "next": null, "previous": null, "results": [{"display_name": "Foo"}]}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let page: PaginatedResponse<Widget> = try await client.get("widgets/")

        #expect(page.count == 1)
        #expect(page.results.first?.displayName == "Foo")
    }

    @Test("attaches query items and the Authorization header")
    func attachesQueryAndAuthorizationHeader() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.query?.contains("updated_at__gte=2026-01-01") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "DeviceToken abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let _: PaginatedResponse<Widget> = try await client.get(
            "widgets/",
            query: [URLQueryItem(name: "updated_at__gte", value: "2026-01-01")],
            authorizationHeader: "DeviceToken abc123"
        )
    }

    @Test("throws APIError.http on a non-2xx status")
    func throwsOnHTTPError() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        await #expect(throws: APIError.self) {
            let _: PaginatedResponse<Widget> = try await client.get("missing/")
        }
    }

    @Test("setForceOffline(true) throws APIError.transport without ever dispatching a real request")
    func forceOfflineThrowsTransportWithoutDispatching() async throws {
        nonisolated(unsafe) var requestWasMade = false
        StubURLProtocol.handler = { request in
            requestWasMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        await client.setForceOffline(true)
        #expect(await client.isForceOffline)

        await #expect(throws: APIError.self) {
            let _: PaginatedResponse<Widget> = try await client.get("widgets/")
        }
        #expect(requestWasMade == false, "no real request should be dispatched while forced offline")

        await client.setForceOffline(false)
        #expect(await client.isForceOffline == false)
        let page: PaginatedResponse<Widget> = try await client.get("widgets/")
        #expect(page.count == 0)
        #expect(requestWasMade == true, "requests should resume once forceOffline is turned back off")
    }

    @Test("encodes the request body as snake_case JSON")
    func encodesRequestBodyAsSnakeCase() async throws {
        struct CreateWidget: Encodable, Sendable { let displayName: String }

        StubURLProtocol.handler = { request in
            let bodyString = String(data: request.httpBodyOrStream(from: request) ?? Data(), encoding: .utf8) ?? ""
            #expect(bodyString.contains("\"display_name\""))
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"display_name": "Foo"}"#.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let _: Widget = try await client.send("widgets/", method: .post, body: CreateWidget(displayName: "Foo"))
    }
}

extension URLRequest {
    fileprivate func httpBodyOrStream(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}
