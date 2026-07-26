public struct UserProfileDTO: Decodable, Sendable {
    public let id: Int64
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let isStaff: Bool
    public let isSuperuser: Bool
    public let isActive: Bool
    public let dateJoined: String?
    public let lastLogin: String?
    public let hasOrcid: Bool
    public let orcidId: String?
    public let orcidName: String?
}

public struct UpdateProfileRequest: Encodable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var currentPassword: String?

    public init(firstName: String? = nil, lastName: String? = nil, email: String? = nil, currentPassword: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.currentPassword = currentPassword
    }
}

public struct UpdateProfileResponse: Decodable, Sendable {
    public let message: String
    public let user: UserProfileDTO
}

public struct ChangePasswordRequest: Encodable, Sendable {
    public var currentPassword: String
    public var newPassword: String
    public var confirmPassword: String

    public init(currentPassword: String, newPassword: String, confirmPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
        self.confirmPassword = confirmPassword
    }
}

public struct ChangePasswordResponse: Decodable, Sendable {
    public let message: String
}
