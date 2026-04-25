import Foundation

/// Represents a participant in a chat room.
public struct Participant: Codable, Equatable {
    public let id: String
    public let externalUserId: String
    public let displayName: String?
    public let locale: String?
    public let role: ParticipantRole
    public let lastReadAt: Date?
    public let joinedAt: Date

    public init(
        id: String,
        externalUserId: String,
        displayName: String? = nil,
        locale: String? = nil,
        role: ParticipantRole = .member,
        lastReadAt: Date? = nil,
        joinedAt: Date
    ) {
        self.id = id
        self.externalUserId = externalUserId
        self.displayName = displayName
        self.locale = locale
        self.role = role
        self.lastReadAt = lastReadAt
        self.joinedAt = joinedAt
    }
}
