import Foundation
import Combine

/// Main entry point for the RiviumChat SDK.
///
/// This is a headless client that provides all chat functionality
/// without any state management opinions. Use with your preferred
/// state management approach.
///
/// Usage:
/// ```swift
/// let config = RiviumChatConfig(
///     apiKey: "your-api-key",
///     userId: "user-123",
///     userInfo: ["displayName": "John Doe"]
/// )
///
/// let client = RiviumChatClient(config: config)
/// try await client.connect()
///
/// // Listen for messages
/// client.onMessage
///     .sink { message in
///         print("New message: \(message.content)")
///     }
///     .store(in: &cancellables)
///
/// // Send a message
/// let message = try await client.sendMessage(roomId, content: "Hello!")
/// ```
public class RiviumChatClient {
    public let config: RiviumChatConfig
    private let apiService: ApiService
    private let realtimeService: RealtimeService
    private var isDisposed = false

    private let authErrorSubject = PassthroughSubject<AuthErrorEvent, Never>()

    /// Identity errors a token refresh cannot fix (revoked or invalid token,
    /// project requires a token, tokenProvider failing). Send the user to
    /// login. Only emitted when ``RiviumChatConfig/tokenProvider`` is set.
    public var onAuthError: AnyPublisher<AuthErrorEvent, Never> {
        authErrorSubject.eraseToAnyPublisher()
    }

    public init(config: RiviumChatConfig) {
        self.config = config
        self.apiService = ApiService(config: config)
        let api = self.apiService
        self.realtimeService = RealtimeService(config) { [config] in
            // With a tokenProvider the same user token authenticates REST and
            // the realtime connection; centrifuge asks again before it expires.
            if let userToken = try await api.userTokenOrNil() { return userToken }
            return try await api.getCentrifugoToken(config.userId, info: config.userInfo)
        }
        self.apiService.onAuthError = { [weak self] event in
            self?.authErrorSubject.send(event)
        }
    }

    // MARK: - Connection

    /// Current connection state.
    public var connectionState: ConnectionState {
        realtimeService.currentConnectionState
    }

    /// Publisher for connection state changes.
    public var onConnectionStateChange: AnyPublisher<ConnectionState, Never> {
        realtimeService.connectionState
    }

    /// Connect to the RiviumChat realtime server.
    public func connect() async throws {
        checkDisposed()
        try await realtimeService.connect()
    }

    /// Disconnect from the RiviumChat realtime server.
    public func disconnect() {
        checkDisposed()
        realtimeService.disconnect()
    }

    /// Whether the client is connected.
    public var isConnected: Bool {
        realtimeService.currentConnectionState == .connected
    }

    // MARK: - Event Publishers

    /// Publisher for new messages.
    public var onMessage: AnyPublisher<Message, Never> {
        realtimeService.onMessage
    }

    /// Publisher for read receipts.
    public var onReadReceipt: AnyPublisher<ReadReceipt, Never> {
        realtimeService.onReadReceipt
    }

    /// Publisher for message deletions.
    public var onMessageDeleted: AnyPublisher<MessageDeletion, Never> {
        realtimeService.onMessageDeleted
    }

    /// Publisher for typing indicators.
    public var onTypingEvent: AnyPublisher<TypingEvent, Never> {
        realtimeService.onTypingEvent
    }

    /// Publisher for presence changes.
    public var onPresenceChange: AnyPublisher<PresenceEvent, Never> {
        realtimeService.onPresenceChange
    }

    /// Publisher for reactions.
    public var onReactionEvent: AnyPublisher<ReactionEvent, Never> {
        realtimeService.onReactionEvent
    }

    /// Publisher for message edits.
    public var onMessageEdited: AnyPublisher<MessageEditEvent, Never> {
        realtimeService.onMessageEdited
    }

    /// Publisher for message pin changes.
    public var onMessagePinChanged: AnyPublisher<MessagePinEvent, Never> {
        realtimeService.onMessagePinChanged
    }

    /// Publisher for connection errors.
    public var onConnectionError: AnyPublisher<ConnectionErrorEvent, Never> {
        realtimeService.onConnectionError
    }

    /// Publisher for subscription state changes.
    public var onSubscriptionState: AnyPublisher<SubscriptionStateEvent, Never> {
        realtimeService.onSubscriptionState
    }

    /// Publisher for recovery failures (room IDs that need full message refresh).
    public var onRecoveryFailed: AnyPublisher<String, Never> {
        realtimeService.onRecoveryFailed
    }

    // MARK: - Room Subscriptions

    /// Subscribes to realtime events for a room.
    public func subscribeRoom(_ roomId: String) {
        checkDisposed()
        realtimeService.subscribeRoom(roomId)
    }

    /// Subscribes only to a room's chat channel for messages/read receipts, without joining presence or typing.
    public func observeRoom(_ roomId: String) {
        checkDisposed()
        realtimeService.observeRoom(roomId)
    }

    /// Unsubscribes from a room's realtime events.
    public func unsubscribeRoom(_ roomId: String) {
        checkDisposed()
        realtimeService.unsubscribeRoom(roomId)
    }

    /// Leaves a room's presence and typing channels but keeps the chat channel for unread updates.
    public func leaveRoom(_ roomId: String) {
        checkDisposed()
        realtimeService.leaveRoom(roomId)
    }

    /// Gets currently online users in a room.
    public func getRoomPresence(_ roomId: String) async throws -> Set<String> {
        checkDisposed()
        return try await realtimeService.getRoomPresence(roomId)
    }

    /// Publishes a typing indicator.
    public func publishTyping(_ roomId: String) {
        checkDisposed()
        realtimeService.publishTyping(roomId)
    }

    // MARK: - Room Operations

    /// Creates a new chat room.
    public func createRoom(
        type: RoomType = .direct,
        name: String? = nil,
        participants: [[String: Any]],
        metadata: [String: Any]? = nil
    ) async throws -> Room {
        checkDisposed()
        return try await apiService.createRoom(type: type, name: name, participants: participants, metadata: metadata)
    }

    /// Finds an existing room by external ID or creates a new one.
    public func findOrCreateRoom(
        externalId: String,
        type: RoomType = .direct,
        name: String? = nil,
        participants: [[String: Any]],
        metadata: [String: Any]? = nil
    ) async throws -> Room {
        checkDisposed()
        return try await apiService.findOrCreateRoom(
            externalId: externalId,
            type: type,
            name: name,
            participants: participants,
            metadata: metadata
        )
    }

    /// Gets a room by its external ID.
    public func getRoomByExternalId(_ externalId: String) async throws -> Room {
        checkDisposed()
        return try await apiService.getRoomByExternalId(externalId)
    }

    /// Lists all rooms for the current user.
    public func listRooms() async throws -> [Room] {
        checkDisposed()
        return try await apiService.listRooms(config.userId)
    }

    /// Gets a room by ID.
    public func getRoom(_ roomId: String) async throws -> Room {
        checkDisposed()
        return try await apiService.getRoom(roomId)
    }

    /// Adds a participant to a room.
    public func addParticipant(
        _ roomId: String,
        externalUserId: String,
        displayName: String? = nil,
        locale: String? = nil,
        role: ParticipantRole = .member
    ) async throws -> Participant {
        checkDisposed()
        return try await apiService.addParticipant(roomId, externalUserId: externalUserId, displayName: displayName, locale: locale, role: role)
    }

    // MARK: - Message Operations

    /// Sends a message to a room.
    public func sendMessage(
        _ roomId: String,
        content: String,
        type: MessageType = .text,
        attachments: [Attachment]? = nil,
        metadata: [String: Any]? = nil,
        replyToId: String? = nil
    ) async throws -> Message {
        checkDisposed()
        return try await apiService.sendMessage(
            roomId,
            senderUserId: config.userId,
            content: content,
            type: type,
            attachments: attachments,
            metadata: metadata,
            replyToId: replyToId
        )
    }

    /// Gets messages for a room with pagination.
    public func getMessages(
        _ roomId: String,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> PaginatedMessages {
        checkDisposed()
        return try await apiService.getMessages(roomId, userId: config.userId, limit: limit, before: before)
    }

    /// Marks messages in a room as read.
    public func markAsRead(_ roomId: String) async throws {
        checkDisposed()
        try await apiService.markAsRead(roomId, config.userId)
    }

    /// Deletes a message.
    public func deleteMessage(_ messageId: String) async throws {
        checkDisposed()
        try await apiService.deleteMessage(messageId, config.userId)
    }

    /// Edits a message.
    public func editMessage(_ messageId: String, content: String) async throws -> Message {
        checkDisposed()
        return try await apiService.editMessage(messageId, userId: config.userId, content: content)
    }

    /// Searches messages in a room.
    public func searchMessages(
        _ roomId: String,
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        checkDisposed()
        return try await apiService.searchMessages(roomId, userId: config.userId, query: query, limit: limit, offset: offset)
    }

    // MARK: - Reaction Operations

    /// Adds a reaction to a message.
    public func addReaction(_ messageId: String, emoji: String) async throws -> Reaction {
        checkDisposed()
        return try await apiService.addReaction(messageId, userId: config.userId, emoji: emoji)
    }

    /// Removes a reaction from a message.
    public func removeReaction(_ messageId: String, emoji: String) async throws {
        checkDisposed()
        try await apiService.removeReaction(messageId, userId: config.userId, emoji: emoji)
    }

    /// Gets all reactions for a message.
    public func getReactions(_ messageId: String) async throws -> [Reaction] {
        checkDisposed()
        return try await apiService.getReactions(messageId)
    }

    // MARK: - Pin Operations

    /// Pins a message.
    public func pinMessage(_ messageId: String) async throws -> Message {
        checkDisposed()
        return try await apiService.pinMessage(messageId, userId: config.userId)
    }

    /// Unpins a message.
    public func unpinMessage(_ messageId: String) async throws {
        checkDisposed()
        try await apiService.unpinMessage(messageId, userId: config.userId)
    }

    /// Gets all pinned messages in a room.
    public func getPinnedMessages(_ roomId: String) async throws -> [Message] {
        checkDisposed()
        return try await apiService.getPinnedMessages(roomId)
    }

    // MARK: - Other Operations

    /// Gets unread message summary for the current user.
    public func getUnreadSummary() async throws -> UnreadSummary {
        checkDisposed()
        return try await apiService.getUnreadSummary(config.userId)
    }

    /// Gets messages where the current user was mentioned.
    public func getMentions(
        _ roomId: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        checkDisposed()
        return try await apiService.getMentions(roomId, userId: config.userId, limit: limit, offset: offset)
    }

    // MARK: - Lifecycle

    private func checkDisposed() {
        if isDisposed {
            fatalError("RiviumChatClient has been disposed")
        }
    }

    /// Disposes all resources.
    public func dispose() {
        if isDisposed { return }
        isDisposed = true
        realtimeService.dispose()
        apiService.dispose()
    }
}
