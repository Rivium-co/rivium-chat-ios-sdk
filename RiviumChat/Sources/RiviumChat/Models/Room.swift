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

    public init(
        id: String,
        type: RoomType = .direct,
        externalId: String? = nil,
        name: String? = nil,
        metadata: [String: String]? = nil,
        isActive: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        participants: [Participant] = []
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
    }
}
