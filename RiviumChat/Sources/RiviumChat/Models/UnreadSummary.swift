import Foundation

/// Summary of unread messages across all rooms.
public struct UnreadSummary: Codable, Equatable {
    public let totalUnread: Int
    public let rooms: [RoomUnread]

    public init(totalUnread: Int, rooms: [RoomUnread]) {
        self.totalUnread = totalUnread
        self.rooms = rooms
    }
}

/// Unread count for a specific room.
public struct RoomUnread: Codable, Equatable {
    public let roomId: String
    public let externalId: String?
    public let unreadCount: Int

    public init(roomId: String, externalId: String? = nil, unreadCount: Int) {
        self.roomId = roomId
        self.externalId = externalId
        self.unreadCount = unreadCount
    }
}
