/// Field names verified directly against `ccrv/serializers.py`'s `SessionAnnotationSerializer`.
/// Read-only cache for Phase 1 — offline create (and the `create_metadata_table`/
/// `add_metadata_column` ontology-tagging actions) land in Phase 4.
public struct SessionAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let annotationText: String
    public let annotationType: String
    public let order: Int
}
