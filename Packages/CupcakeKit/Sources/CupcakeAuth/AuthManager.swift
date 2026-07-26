import CupcakeNetworking
import Foundation

public actor AuthManager {
    private let authService: AuthService
    private let keychain: KeychainStore

    public init(authService: AuthService, keychain: KeychainStore = KeychainStore()) {
        self.authService = authService
        self.keychain = keychain
    }

    @discardableResult
    public func signIn(username: String, password: String, deviceLabel: String) async throws -> (deviceToken: DeviceTokenDTO, user: AuthUserDTO) {
        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: deviceLabel
        )
        try keychain.save(deviceToken.token)
        return (deviceToken, login.user)
    }

    public nonisolated func orcidLoginURL() -> URL {
        authService.orcidLoginURL()
    }

    @discardableResult
    public func completeORCIDSignIn(authCode: String, deviceLabel: String) async throws -> (deviceToken: DeviceTokenDTO, user: AuthUserDTO) {
        let login = try await authService.exchangeAuthCode(authCode)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: deviceLabel
        )
        try keychain.save(deviceToken.token)
        return (deviceToken, login.user)
    }

    public func storedDeviceToken() -> String? {
        keychain.load()
    }

    public func signOut() {
        keychain.delete()
    }
}
