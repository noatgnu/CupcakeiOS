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
