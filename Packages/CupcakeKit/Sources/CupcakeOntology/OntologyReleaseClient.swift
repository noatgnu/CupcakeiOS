import Foundation

/// Talks to `api.github.com`'s public, unauthenticated Releases API for `noatgnu/cupcake-webgui`, not the Cupcake backend.
public actor OntologyReleaseClient {
    private let session: URLSession
    private static let releaseURL = URL(string: "https://api.github.com/repos/noatgnu/cupcake-webgui/releases/latest")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the latest release's asset list and downloads+decodes the one asset named `"manifest-*"`.
    public func fetchManifest() async throws -> OntologyManifest {
        let assets = try await fetchLatestReleaseAssets()
        guard let manifestAsset = assets.first(where: { $0.name.hasPrefix("manifest-") }) else {
            throw OntologyReleaseError.manifestAssetNotFound
        }
        let (data, response) = try await session.data(from: manifestAsset.browserDownloadURL)
        try Self.validate(response)
        return try JSONDecoder().decode(OntologyManifest.self, from: data)
    }

    /// Downloads and gzip-decompresses one table's `.sqlite.gz` asset, matched by `table.file`.
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
