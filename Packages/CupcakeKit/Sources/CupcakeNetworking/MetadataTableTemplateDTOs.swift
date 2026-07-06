/// Verified against `ccv/models.py:2328-2457` (`BaseMetadataTableTemplate`/`MetadataTableTemplate`)
/// and `MetadataTableTemplateSerializer` (`ccv/serializers.py:279-310`). Read-only browsing in
/// this app's v1 slice — column authoring (`add_column`/`remove_column`/etc.) isn't in scope; a
/// job only ever needs a `template_id` to hand to `create_metadata_from_template`.
public struct MetadataTableTemplateDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let ownerUsername: String?
    public let visibility: String
    public let isDefault: Bool
    public let columnCount: Int
}
