/// Verified against `ccc/models.py:790-1092` (`LabGroup`) and `LabGroupSerializer`
/// (`ccc/serializers.py:170-215`). Read-only in this app — no create/edit path yet.
/// `members` isn't exposed on this serializer (only via a separate `members` action), so it's
/// not modeled here.
public struct LabGroupDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let allowProcessJobs: Bool
}

/// `GET lab-groups/{id}/members/?direct_only=true` response entry. Verified against
/// `UserSerializer` (`ccc/serializers.py`) and the real response body directly — only the
/// fields this app's staff-picker actually needs are modeled.
public struct UserDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let username: String
    public let firstName: String?
    public let lastName: String?
}
