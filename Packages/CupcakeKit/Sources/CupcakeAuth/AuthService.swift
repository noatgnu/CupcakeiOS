import CupcakeNetworking
import Foundation

/// Raw calls for the two bootstrap requests. Kept separate from `AuthManager` so the
/// login→device-token exchange sequencing (and Keychain persistence) can be tested independently
/// of the actual HTTP round-trip.
public actor AuthService {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func login(username: String, password: String, rememberMe: Bool = false) async throws -> LoginResponse {
        try await apiClient.send(
            "auth/login/",
            method: .post,
            body: LoginRequest(username: username, password: password, rememberMe: rememberMe)
        )
    }

    /// Where a native client points its whole `ASWebAuthenticationSession` (not a plain GET to fetch JSON first) — `client_type=mobile` makes the backend redirect straight to ORCID instead.
    public nonisolated func orcidLoginURL() -> URL {
        apiClient.baseURL
            .appendingPathComponent("auth/orcid/login/")
            .appending(queryItems: [URLQueryItem(name: "client_type", value: "mobile")])
    }

    /// Trades the opaque `auth_code` from the callback redirect for real JWTs.
    public func exchangeAuthCode(_ authCode: String) async throws -> LoginResponse {
        try await apiClient.send(
            "auth/exchange-code/",
            method: .post,
            body: ExchangeAuthCodeRequest(authCode: authCode)
        )
    }

    /// Must be called with the JWT access token from `login(...)` — `device-tokens/` also
    /// accepts an existing `DeviceToken` with write permission, but that's not this bootstrap path.
    public func createDeviceToken(
        accessToken: String,
        label: String,
        permission: String = "write"
    ) async throws -> DeviceTokenDTO {
        try await apiClient.send(
            "device-tokens/",
            method: .post,
            body: DeviceTokenCreateRequest(label: label, permission: permission),
            authorizationHeader: "Bearer \(accessToken)"
        )
    }
}
