import Foundation

/// DRF `LimitOffsetPagination` envelope. Every list endpoint in the backend returns this shape,
/// with `limit`/`offset` query params (not `page`/`page_size`) — confirmed against
/// `cupcake_vanilla/settings.py`'s `DEFAULT_PAGINATION_CLASS`.
public struct PaginatedResponse<Result: Decodable & Sendable>: Decodable, Sendable {
    public let count: Int
    public let next: String?
    public let previous: String?
    public let results: [Result]
}
