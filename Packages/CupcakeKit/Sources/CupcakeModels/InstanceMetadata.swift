import Foundation
import SwiftData

@Model
public final class InstanceMetadata {
    @Attribute(.unique) public var singletonKey: String
    public var currentUserID: Int64?
    public var isStaff: Bool
    public var baseURLString: String?
    public var username: String?
    public var email: String?
    public var firstName: String?
    public var lastName: String?

    public init(
        singletonKey: String = "singleton",
        currentUserID: Int64? = nil,
        isStaff: Bool = false,
        baseURLString: String? = nil,
        username: String? = nil,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil
    ) {
        self.singletonKey = singletonKey
        self.currentUserID = currentUserID
        self.isStaff = isStaff
        self.baseURLString = baseURLString
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
    }
}
