/// Field names verified directly against `ccrv/serializers.py`'s `SessionSerializer`. `id` (not
/// `unique_id`) is the real lookup key — `SessionViewSet` has no `lookup_field` override, so it
/// uses DRF's default `pk` routing. `unique_id` is a separate, server-generated UUID kept only
/// for display/external reference.
///
/// `name` is a nullable `TextField` server-side. `isRunning` (`get_is_running` in
/// `SessionSerializer`) is `obj.started_at and not obj.ended_at` — Python's `and` returns the
/// left operand verbatim when it's falsy, so an unstarted session (`started_at is None`)
/// serializes `is_running` as JSON `null`, not `false`. Both must be optional or this DTO fails
/// to decode the single most common case: a session that hasn't been started yet.
public struct SessionDTO: Decodable, Sendable {
    public let id: Int64
    public let uniqueId: String
    public let name: String?
    public let enabled: Bool
    public let processing: Bool
    public let startedAt: String?
    public let endedAt: String?
    public let isRunning: Bool?
    public let status: String
    public let protocols: [Int64]
}

/// `POST sessions/` body. `owner`/`unique_id` are server-assigned
/// (`SessionCreateSerializer.create()` forces both, overriding anything sent). Field set matches
/// the reference web app's `session-create-modal.ts` exactly: `name` + `enabled` ("Public" in
/// the web UI) — the session is always tied to the current protocol, never user-picked.
public struct CreateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool
    public var protocols: [Int64]

    public init(name: String, enabled: Bool = true, protocols: [Int64] = []) {
        self.name = name
        self.enabled = enabled
        self.protocols = protocols
    }
}
