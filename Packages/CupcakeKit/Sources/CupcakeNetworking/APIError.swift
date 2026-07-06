import Foundation

public enum APIError: Error {
    case invalidURL
    case transport(underlying: any Error)
    /// Non-2xx response. `body` is kept raw since error payload shapes vary by endpoint.
    case http(status: Int, body: Data)
    case decoding(underlying: any Error, body: Data)
}

extension APIError {
    /// Extracts DRF's actual rejection message from an `.http` error's body, rather than the
    /// generic "The operation couldn't be completed (CupcakeNetworking.APIError error N.)" that
    /// `localizedDescription` gives by default — confirmed live that this generic message was
    /// genuinely shown to users for real, informative rejections (e.g. a staff-assignment
    /// permission error, an instrument-booking overlap rejection) that name exactly what's wrong
    /// and would otherwise be silently discarded. Two real DRF shapes confirmed live, not assumed
    /// from documentation: field/`non_field_errors` validation errors are `{"field": ["msg",
    /// ...]}` (values are always arrays, even for a single message); permission errors and custom
    /// `@action` responses are `{"detail": "msg"}` or `{"error": "msg"}` (plain strings). Falls
    /// back to `localizedDescription` for anything else (a non-JSON body, a `.transport`/
    /// `.decoding` error, or an unrecognized shape).
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
    /// Lets every catch site use one call regardless of whether it narrowed to `APIError`
    /// (`catch let error as APIError`) or stayed generic (`catch`) — most of this app's ~16
    /// call sites use the latter, and restructuring every one of them into a narrowed catch
    /// purely to reach `APIError.userFacingMessage` would be needless churn for what's really a
    /// one-line improvement at each site.
    public var userFacingMessage: String {
        (self as? APIError)?.userFacingMessage ?? localizedDescription
    }
}
