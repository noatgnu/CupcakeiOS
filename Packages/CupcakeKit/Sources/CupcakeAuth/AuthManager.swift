import CupcakeNetworking

/// The single entry point the app UI calls. Username/password authenticates exactly once,
/// immediately exchanged for a `write`-permission `DeviceToken` that's used for all REST traffic
/// afterward — the JWT pair from `login` is discarded once the exchange succeeds, not retained
/// for refresh.
public actor AuthManager {
    private let authService: AuthService
    private let keychain: KeychainStore

    public init(authService: AuthService, keychain: KeychainStore = KeychainStore()) {
        self.authService = authService
        self.keychain = keychain
    }

    /// `deviceLabel` should identify the physical device (e.g. its `UIDevice.current.name` /
    /// `Host.current().localizedName`) so a user reviewing `/home/devices` on the web app later
    /// can tell which entry to revoke.
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

    public func storedDeviceToken() -> String? {
        keychain.load()
    }

    public func signOut() {
        keychain.delete()
    }
}
