import Foundation

/// Represents a demo user for the e-commerce example.
public struct DemoUser: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let role: UserRole
    public let avatarUrl: String?

    public init(id: String, name: String, role: UserRole, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.avatarUrl = avatarUrl
    }
}

public enum UserRole: String, CaseIterable {
    case buyer = "BUYER"
    case seller = "SELLER"
}

/// Demo users for the example app.
public struct DemoUsers {
    public static let buyer = DemoUser(
        id: "buyer-001",
        name: "John Buyer",
        role: .buyer,
        avatarUrl: "https://api.dicebear.com/7.x/avataaars/png?seed=buyer001"
    )

    public static let seller = DemoUser(
        id: "seller-001",
        name: "Sarah Seller",
        role: .seller,
        avatarUrl: "https://api.dicebear.com/7.x/avataaars/png?seed=seller001"
    )

    public static func all() -> [DemoUser] {
        [buyer, seller]
    }

    public static func getOtherUser(currentUserId: String) -> DemoUser {
        currentUserId == buyer.id ? seller : buyer
    }
}
