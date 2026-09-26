import Foundation

/// Represents a chat room (conversation).
public struct Room: Codable, Equatable {
    public let id: String
    public let type: RoomType
    public let externalId: String?
    public let name: String?
    public let metadata: [String: String]?
    public let isActive: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let participants: [Participant]
    /// The most recent message in the room, or nil when there are none. Sent by
    /// `GET /rooms`, so a chat list can show a preview without loading each
    /// room's messages.
    public let lastMessage: Message?
    /// Messages from other people that arrived after this user last read the
    /// room. Sent by `GET /rooms`; 0 when everything has been read.
    public let unreadCount: Int

    public init(
        id: String,
        type: RoomType = .direct,
        externalId: String? = nil,
        name: String? = nil,
        metadata: [String: String]? = nil,
        isActive: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        participants: [Participant] = [],
        lastMessage: Message? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.externalId = externalId
        self.name = name
        self.metadata = metadata
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }

    // Both fields only arrive from `GET /rooms`; every other endpoint returns a
    // room without them, so decoding must not fail when they are absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(RoomType.self, forKey: .type) ?? .direct
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        participants = try container.decodeIfPresent([Participant].self, forKey: .participants) ?? []
        lastMessage = try container.decodeIfPresent(Message.self, forKey: .lastMessage)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}
