import Foundation

public enum APIError: Error {
    case invalidURL
    case transport(underlying: any Error)
    /// Non-2xx response. `body` is kept raw since error payload shapes vary by endpoint.
    case http(status: Int, body: Data)
    case decoding(underlying: any Error, body: Data)
}

extension APIError {
    /// Extracts DRF's actual rejection message from an `.http` error's body, falling back to `localizedDescription`.
    public var userFacingMessage: String {
        guard case let .http(_, body) = self else {
            return (self as Error).localizedDescription
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (self as Error).localizedDescription
        }

        var messages: [String] = []
        for (field, value) in json {
            if let strings = value as? [String] {
                messages.append(contentsOf: strings.map { field == "non_field_errors" || field == "detail" || field == "error" ? $0 : "\(field): \($0)" })
            } else if let string = value as? String {
                messages.append(field == "detail" || field == "error" ? string : "\(field): \(string)")
            }
        }
        guard !messages.isEmpty else {
            return (self as Error).localizedDescription
        }
        return messages.joined(separator: "\n")
    }
}

extension Error {
    /// Lets any catch site use one call regardless of whether it narrowed to `APIError`.
    public var userFacingMessage: String {
        (self as? APIError)?.userFacingMessage ?? localizedDescription
    }
}
