import Foundation

/// Event emitted when a user reads messages in a room.
public struct ReadReceipt: Equatable {
    public let userId: String
    public let roomId: String
    public let readAt: Date

    public init(userId: String, roomId: String, readAt: Date) {
        self.userId = userId
        self.roomId = roomId
        self.readAt = readAt
    }
}

/// Event emitted when a message is deleted.
public struct MessageDeletion: Equatable {
    public let messageId: String
    public let roomId: String
    public let deletedBy: String

    public init(messageId: String, roomId: String, deletedBy: String) {
        self.messageId = messageId
        self.roomId = roomId
        self.deletedBy = deletedBy
    }
}

/// Event emitted when a user is typing.
public struct TypingEvent: Equatable {
    public let roomId: String
    public let userId: String
    public let isTyping: Bool

    public init(roomId: String, userId: String, isTyping: Bool = true) {
        self.roomId = roomId
        self.userId = userId
        self.isTyping = isTyping
    }
}

/// Event emitted when a reaction is added or removed.
public struct ReactionEvent: Equatable {
    public let messageId: String
    public let roomId: String
    public let userId: String
    public let emoji: String
    public let added: Bool
    public let reactionId: String?

    public init(messageId: String, roomId: String, userId: String, emoji: String, added: Bool, reactionId: String? = nil) {
        self.messageId = messageId
        self.roomId = roomId
        self.userId = userId
        self.emoji = emoji
        self.added = added
        self.reactionId = reactionId
    }
}

/// Event emitted when a message is edited.
public struct MessageEditEvent: Equatable {
    public let messageId: String
    public let roomId: String
    public let content: String
    public let editedBy: String
    public let editedAt: Date

    public init(messageId: String, roomId: String, content: String, editedBy: String, editedAt: Date) {
        self.messageId = messageId
        self.roomId = roomId
        self.content = content
        self.editedBy = editedBy
        self.editedAt = editedAt
    }
}

/// Event emitted when a message is pinned or unpinned.
public struct MessagePinEvent: Equatable {
    public let messageId: String
    public let roomId: String
    public let userId: String
    public let pinned: Bool

    public init(messageId: String, roomId: String, userId: String, pinned: Bool) {
        self.messageId = messageId
        self.roomId = roomId
        self.userId = userId
        self.pinned = pinned
    }
}

/// Event emitted when user presence changes.
public struct PresenceEvent: Equatable {
    public let roomId: String
    public let userId: String
    public let isOnline: Bool

    public init(roomId: String, userId: String, isOnline: Bool) {
        self.roomId = roomId
        self.userId = userId
        self.isOnline = isOnline
    }
}

/// Event emitted when a connection error occurs.
public struct ConnectionErrorEvent {
    public let error: Any

    public init(error: Any) {
        self.error = error
    }
}

/// Event emitted when subscription state changes.
public struct SubscriptionStateEvent {
    public let roomId: String
    public let channel: String
    public let status: SubscriptionStatus
    public let code: Int?
    public let reason: String?

    public init(roomId: String, channel: String, status: SubscriptionStatus, code: Int? = nil, reason: String? = nil) {
        self.roomId = roomId
        self.channel = channel
        self.status = status
        self.code = code
        self.reason = reason
    }
}
