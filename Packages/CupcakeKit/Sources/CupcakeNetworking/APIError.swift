import Foundation

public enum APIError: Error {
    case invalidURL
    case transport(underlying: any Error)
    /// Non-2xx response. `body` is kept raw since error payload shapes vary by endpoint.
    case http(status: Int, body: Data)
    case decoding(underlying: any Error, body: Data)
}
