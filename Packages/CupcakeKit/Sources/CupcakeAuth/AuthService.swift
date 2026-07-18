import CupcakeNetworking
import Foundation

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

    public nonisolated func orcidLoginURL() -> URL {
        apiClient.baseURL
            .appendingPathComponent("auth/orcid/login/")
            .appending(queryItems: [URLQueryItem(name: "client_type", value: "mobile")])
    }

    public func exchangeAuthCode(_ authCode: String) async throws -> LoginResponse {
        try await apiClient.send(
            "auth/exchange-code/",
            method: .post,
            body: ExchangeAuthCodeRequest(authCode: authCode)
        )
    }

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
