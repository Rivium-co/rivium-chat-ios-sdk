import Foundation

/// Message content types supported by RiviumChat.
public enum MessageType: String, Codable {
    case text
    case image
    case file
    case system
}

/// Room types for conversations.
public enum RoomType: String, Codable {
    case direct
    case group
}

/// Participant roles within a room.
public enum ParticipantRole: String, Codable {
    case admin
    case member
}

/// Connection states for the realtime service.
public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error
}

/// Subscription states for room channels.
public enum SubscriptionStatus: Equatable {
    case subscribing
    case subscribed
    case unsubscribed
}
