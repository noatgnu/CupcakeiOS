import Foundation

/// The GitHub release manifest listing every ontology/column-template/schema table asset.
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
