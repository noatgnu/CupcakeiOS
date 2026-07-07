import Foundation

/// DRF `LimitOffsetPagination` envelope used by every list endpoint (`limit`/`offset` query params).
public struct PaginatedResponse<Result: Decodable & Sendable>: Decodable, Sendable {
    public let count: Int
    public let next: String?
    public let previous: String?
    public let results: [Result]
}
