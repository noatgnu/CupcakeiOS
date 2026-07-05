import Foundation

/// Shape verified directly against a real downloaded `manifest-v0.0.2.json` from
/// `noatgnu/cupcake-webgui`'s releases — not assumed from a spec. `file` (not `filename`) is the
/// per-table asset's exact GitHub release asset name; `dataset` is `"ontology"` for the 14
/// per-type_key tables, `"column-template"` for the single `column-template-system.sqlite.gz`
/// (name `"system"`), and `"schema"` for the single `schema-sdrf.sqlite.gz` (name `"sdrf"`).
public struct OntologyManifest: Decodable, Sendable {
    public let formatVersion: Int
    public let tables: [OntologyManifestTable]

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case tables
    }
}

public struct OntologyManifestTable: Decodable, Sendable {
    public let dataset: String
    public let name: String
    public let file: String
    public let rowCount: Int
    public let uncompressedBytes: Int64
    public let compressedBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case dataset, name, file
        case rowCount = "row_count"
        case uncompressedBytes = "uncompressed_bytes"
        case compressedBytes = "compressed_bytes"
    }
}
