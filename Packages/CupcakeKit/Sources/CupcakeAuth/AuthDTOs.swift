/// `POST auth/login/` request body.
public struct LoginRequest: Encodable, Sendable {
    public var username: String
    public var password: String
    public var rememberMe: Bool

    public init(username: String, password: String, rememberMe: Bool = false) {
        self.username = username
        self.password = password
        self.rememberMe = rememberMe
    }
}

/// `POST auth/login/` response. Field names are `access_token`/`refresh_token`, not the plain SimpleJWT shape.
public struct LoginResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let user: AuthUserDTO
}

public struct AuthUserDTO: Decodable, Sendable {
    public let id: Int
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let isStaff: Bool
    public let isSuperuser: Bool
}

/// `POST device-tokens/` request body. `token`/`user` are server-assigned and never sent.
public struct DeviceTokenCreateRequest: Encodable, Sendable {
    public var label: String
    public var description: String
    public var permission: String

    public init(label: String, description: String = "", permission: String = "write") {
        self.label = label
        self.description = description
        self.permission = permission
    }
}

/// `POST auth/exchange-code/` request body — trades the ORCID callback's opaque code for real JWTs.
public struct ExchangeAuthCodeRequest: Encodable, Sendable {
    public var authCode: String

    public init(authCode: String) {
        self.authCode = authCode
    }
}

/// `DeviceToken` as returned by the backend. Timestamps are kept as raw strings, not `Date`.
public struct DeviceTokenDTO: Decodable, Sendable {
    public let id: Int
    public let token: String
    public let label: String
    public let description: String
    public let permission: String
    public let enabled: Bool
    public let user: Int
    public let username: String
    public let createdAt: String
    public let lastUsedAt: String?
    public let expiresAt: String?
    public let isExpired: Bool
}
