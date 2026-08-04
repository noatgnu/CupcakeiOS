import CupcakeAuth
import CupcakeNetworking
import Foundation

public actor DeviceTokenSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func fetchPage(offset: Int, limit: Int) async throws -> PaginatedResponse<DeviceTokenDTO> {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        return try await apiClient.get(
            "device-tokens/",
            query: [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func create(label: String, description: String, permission: String, expiresAt: String? = nil) async throws -> DeviceTokenDTO {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "device-tokens/",
            method: .post,
            body: DeviceTokenCreateRequest(label: label, description: description, permission: permission, expiresAt: expiresAt),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func update(id: Int, label: String?, description: String?, permission: String?) async throws -> DeviceTokenDTO {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "device-tokens/\(id)/",
            method: .patch,
            body: UpdateDeviceTokenRequest(label: label, description: description, permission: permission),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func rotate(id: Int) async throws -> String {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        let response: RotateDeviceTokenResponse = try await apiClient.send(
            "device-tokens/\(id)/rotate/",
            method: .post,
            body: EmptyEncodable(),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.token
    }

    @discardableResult
    public func toggle(id: Int) async throws -> Bool {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        let response: ToggleDeviceTokenResponse = try await apiClient.send(
            "device-tokens/\(id)/toggle/",
            method: .post,
            body: EmptyEncodable(),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.enabled
    }

    public func delete(id: Int) async throws {
        guard let token = deviceToken() else {
            throw DeviceTokenSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("device-tokens/\(id)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
    }

}

private struct EmptyEncodable: Encodable, Sendable {}

public enum DeviceTokenSyncError: Error {
    case noDeviceToken
}
