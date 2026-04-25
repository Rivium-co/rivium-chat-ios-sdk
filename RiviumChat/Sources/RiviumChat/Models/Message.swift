import Foundation

/// Represents a chat message.
public final class Message: Codable, Equatable, Hashable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.roomId == rhs.roomId &&
        lhs.senderUserId == rhs.senderUserId &&
        lhs.content == rhs.content &&
        lhs.type == rhs.type &&
        lhs.replyToId == rhs.replyToId &&
        lhs.isDeleted == rhs.isDeleted &&
        lhs.createdAt == rhs.createdAt &&
        lhs.isEdited == rhs.isEdited &&
        lhs.editedAt == rhs.editedAt &&
        lhs.isPinned == rhs.isPinned &&
        lhs.pinnedAt == rhs.pinnedAt &&
        lhs.pinnedBy == rhs.pinnedBy &&
        lhs.isPending == rhs.isPending &&
        lhs.isFailed == rhs.isFailed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public let id: String
    public let roomId: String
    public let senderUserId: String
    public let content: String
    public let type: MessageType
    public let attachments: [Attachment]?
    public let metadata: [String: String]?
    public let replyToId: String?
    public let replyTo: Message?
    public let isDeleted: Bool
    public let createdAt: Date
    public let isEdited: Bool
    public let editedAt: Date?
    public let editHistory: [[String: String]]?
    public let isPinned: Bool
    public let pinnedAt: Date?
    public let pinnedBy: String?
    public let reactions: [Reaction]?
    // Local state flags (not persisted)
    public let isPending: Bool
    public let isFailed: Bool

    public init(
        id: String,
        roomId: String,
        senderUserId: String,
        content: String,
        type: MessageType = .text,
        attachments: [Attachment]? = nil,
        metadata: [String: String]? = nil,
        replyToId: String? = nil,
        replyTo: Message? = nil,
        isDeleted: Bool = false,
        createdAt: Date,
        isEdited: Bool = false,
        editedAt: Date? = nil,
        editHistory: [[String: String]]? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        pinnedBy: String? = nil,
        reactions: [Reaction]? = nil,
        isPending: Bool = false,
        isFailed: Bool = false
    ) {
        self.id = id
        self.roomId = roomId
        self.senderUserId = senderUserId
        self.content = content
        self.type = type
        self.attachments = attachments
        self.metadata = metadata
        self.replyToId = replyToId
        self.replyTo = replyTo
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.isEdited = isEdited
        self.editedAt = editedAt
        self.editHistory = editHistory
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.pinnedBy = pinnedBy
        self.reactions = reactions
        self.isPending = isPending
        self.isFailed = isFailed
    }

    // Custom encoding/decoding for recursive replyTo
    private enum CodingKeys: String, CodingKey {
        case id, roomId, senderUserId, content, type, attachments, metadata
        case replyToId, replyTo, isDeleted, createdAt, isEdited, editedAt, editHistory
        case isPinned, pinnedAt, pinnedBy, reactions, isPending, isFailed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        roomId = try container.decode(String.self, forKey: .roomId)
        senderUserId = try container.decode(String.self, forKey: .senderUserId)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        type = try container.decodeIfPresent(MessageType.self, forKey: .type) ?? .text
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        replyTo = try container.decodeIfPresent(Message.self, forKey: .replyTo)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        editHistory = try container.decodeIfPresent([[String: String]].self, forKey: .editHistory)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        pinnedBy = try container.decodeIfPresent(String.self, forKey: .pinnedBy)
        reactions = try container.decodeIfPresent([Reaction].self, forKey: .reactions)
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        isFailed = try container.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
    }
}

/// Paginated response for message queries.
public struct PaginatedMessages: Codable {
    public let messages: [Message]
    public let hasMore: Bool

    public init(messages: [Message], hasMore: Bool) {
        self.messages = messages
        self.hasMore = hasMore
    }
}
