import Foundation

/// Represents an emoji reaction on a message.
public struct Reaction: Codable, Equatable {
    public let id: String
    public let messageId: String
    public let userId: String
    public let emoji: String
    public let createdAt: Date

    public init(id: String, messageId: String, userId: String, emoji: String, createdAt: Date) {
        self.id = id
        self.messageId = messageId
        self.userId = userId
        self.emoji = emoji
        self.createdAt = createdAt
    }
}
