import CupcakeNetworking
import Foundation

/// Authenticates once, exchanging the resulting JWT for a `write`-permission `DeviceToken` used for all REST traffic.
public actor AuthManager {
    private let authService: AuthService
    private let keychain: KeychainStore

    public init(authService: AuthService, keychain: KeychainStore = KeychainStore()) {
        self.authService = authService
        self.keychain = keychain
    }

    /// `deviceLabel` should identify the physical device for later review on `/home/devices`.
    @discardableResult
    public func signIn(username: String, password: String, deviceLabel: String) async throws -> DeviceTokenDTO {
        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: deviceLabel
        )
        try keychain.save(deviceToken.token)
        return deviceToken
    }

    /// Where the app should point `ASWebAuthenticationSession` — see `AuthService.orcidLoginURL()`.
    public nonisolated func orcidLoginURL() -> URL {
        authService.orcidLoginURL()
    }

    /// Same exchange-for-device-token tail as `signIn`, starting from an ORCID auth code.
    @discardableResult
    public func completeORCIDSignIn(authCode: String, deviceLabel: String) async throws -> DeviceTokenDTO {
        let login = try await authService.exchangeAuthCode(authCode)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: deviceLabel
        )
        try keychain.save(deviceToken.token)
        return deviceToken
    }

    public func storedDeviceToken() -> String? {
        keychain.load()
    }

    public func signOut() {
        keychain.delete()
    }
}
