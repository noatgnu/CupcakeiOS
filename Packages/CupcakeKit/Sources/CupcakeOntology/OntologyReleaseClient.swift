import Foundation

/// Talks to `api.github.com`, not the Cupcake backend — verified real endpoint:
/// `noatgnu/cupcake-webgui`'s GitHub Releases, confirmed by actually downloading and inspecting
/// a real `manifest-v0.0.2.json` and one full ontology `.sqlite.gz` asset (byte-for-byte
/// round-tripped through this app's own gzip decoder) rather than assumed from a workflow file.
/// No device-token auth needed — this is a public, unauthenticated GitHub API/CDN endpoint.
public actor OntologyReleaseClient {
    private let session: URLSession
    private static let releaseURL = URL(string: "https://api.github.com/repos/noatgnu/cupcake-webgui/releases/latest")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the latest release's asset list and downloads+decodes whichever asset's name
    /// starts with `"manifest-"` — the release always has exactly one (the version suffix
    /// changes per release, e.g. `manifest-v0.0.2.json`).
    public func fetchManifest() async throws -> OntologyManifest {
        let assets = try await fetchLatestReleaseAssets()
        guard let manifestAsset = assets.first(where: { $0.name.hasPrefix("manifest-") }) else {
            throw OntologyReleaseError.manifestAssetNotFound
        }
        let (data, response) = try await session.data(from: manifestAsset.browserDownloadURL)
        try Self.validate(response)
        return try JSONDecoder().decode(OntologyManifest.self, from: data)
    }

    /// Downloads and gzip-decompresses one table's `.sqlite.gz` asset (matched by `table.file`
    /// against the release's actual asset list, not constructed from a guessed URL pattern) —
    /// returns the raw decompressed SQLite file bytes, ready to write to disk and open.
    public func downloadTable(_ table: OntologyManifestTable) async throws -> Data {
        let assets = try await fetchLatestReleaseAssets()
        guard let asset = assets.first(where: { $0.name == table.file }) else {
            throw OntologyReleaseError.tableAssetNotFound(table.file)
        }
        let (data, response) = try await session.data(from: asset.browserDownloadURL)
        try Self.validate(response)
        guard let decompressed = GzipDecoder.decode(data) else {
            throw OntologyReleaseError.decompressionFailed(table.file)
        }
        return decompressed
    }

    private func fetchLatestReleaseAssets() async throws -> [GitHubReleaseAsset] {
        let (data, response) = try await session.data(from: Self.releaseURL)
        try Self.validate(response)
        return try JSONDecoder().decode(GitHubRelease.self, from: data).assets
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OntologyReleaseError.badResponse(response)
        }
    }
}

/// Minimal slice of GitHub's release/asset API response — only what's needed to locate assets.
private struct GitHubRelease: Decodable {
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

public enum OntologyReleaseError: Error {
    case manifestAssetNotFound
    case tableAssetNotFound(String)
    case decompressionFailed(String)
    case badResponse(URLResponse)
}
