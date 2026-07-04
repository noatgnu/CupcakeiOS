/// `POST auth/login/` request body. Confirmed against `ccc/authentication.py:login_view` —
/// distinct from the plain SimpleJWT `auth/token/` endpoint, which doesn't accept `remember_me`.
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

/// `POST auth/login/` response. Field names are `access_token`/`refresh_token` here — the
/// sibling `auth/token/` endpoint instead returns bare `access`/`refresh` (standard SimpleJWT).
/// Getting this wrong silently decodes to a missing-key error, not a wrong-but-plausible value,
/// so it's worth flagging why this DTO doesn't just reuse the other endpoint's shape.
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

/// `DeviceToken` as returned by the backend. `createdAt`/`lastUsedAt`/`expiresAt` are kept as
/// raw strings rather than `Date` — this bootstrap path never needs to display them, and DRF's
/// exact timestamp format isn't worth committing to here (decode failures on unrelated field
/// format drift would break login, not just a display screen).
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
