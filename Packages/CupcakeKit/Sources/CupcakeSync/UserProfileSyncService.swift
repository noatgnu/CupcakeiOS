import CupcakeNetworking
import Foundation

public actor UserProfileSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func fetchProfile(userID: Int64) async throws -> UserProfileDTO {
        guard let token = deviceToken() else {
            throw UserProfileSyncError.noDeviceToken
        }
        return try await apiClient.get("users/\(userID)/", authorizationHeader: "DeviceToken \(token)")
    }

    @discardableResult
    public func updateProfile(firstName: String?, lastName: String?, email: String?, currentPassword: String?) async throws -> UserProfileDTO {
        guard let token = deviceToken() else {
            throw UserProfileSyncError.noDeviceToken
        }
        let response: UpdateProfileResponse = try await apiClient.send(
            "users/update_profile/",
            method: .post,
            body: UpdateProfileRequest(firstName: firstName, lastName: lastName, email: email, currentPassword: currentPassword),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.user
    }

    public func changePassword(currentPassword: String, newPassword: String, confirmPassword: String) async throws {
        guard let token = deviceToken() else {
            throw UserProfileSyncError.noDeviceToken
        }
        let _: ChangePasswordResponse = try await apiClient.send(
            "users/change_password/",
            method: .post,
            body: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword, confirmPassword: confirmPassword),
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

public enum UserProfileSyncError: Error {
    case noDeviceToken
}
