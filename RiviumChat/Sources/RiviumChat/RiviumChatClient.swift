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
    private let outbox: Outbox?
    private let now: () -> Date
    private var connectionCancellable: AnyCancellable?

    private let messageSentSubject = PassthroughSubject<MessageSentEvent, Never>()
    private let messageFailedSubject = PassthroughSubject<MessageFailedEvent, Never>()

    /// A message queued while offline was stored by the server. Only with
    /// ``RiviumChatConfig/queueOfflineMessages``.
    public var onMessageSent: AnyPublisher<MessageSentEvent, Never> {
        messageSentSubject.eraseToAnyPublisher()
    }

    /// A message queued while offline left the queue without being stored
    /// (`reason` "expired" or "rejected"). Only with
    /// ``RiviumChatConfig/queueOfflineMessages``.
    public var onMessageFailed: AnyPublisher<MessageFailedEvent, Never> {
        messageFailedSubject.eraseToAnyPublisher()
    }

    private let authErrorSubject = PassthroughSubject<AuthErrorEvent, Never>()

    /// Identity errors a token refresh cannot fix (revoked or invalid token,
    /// project requires a token, tokenProvider failing). Send the user to
    /// login. Only emitted when ``RiviumChatConfig/tokenProvider`` is set.
    public var onAuthError: AnyPublisher<AuthErrorEvent, Never> {
        authErrorSubject.eraseToAnyPublisher()
    }

    public convenience init(config: RiviumChatConfig) {
        self.init(config: config, sessionConfiguration: .default)
    }

    /// `sessionConfiguration`, `now` and `sleep` let tests answer requests
    /// without a network and control the outbox's clock.
    init(
        config: RiviumChatConfig,
        sessionConfiguration: URLSessionConfiguration,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Outbox.Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.config = config
        self.now = now
        self.apiService = ApiService(config: config, sessionConfiguration: sessionConfiguration)
        let api = self.apiService
        self.realtimeService = RealtimeService(config) { [config] in
            // With a tokenProvider the same user token authenticates REST and
            // the realtime connection; centrifuge asks again before it expires.
            if let userToken = try await api.userTokenOrNil() { return userToken }
            return try await api.getCentrifugoToken(config.userId, info: config.userInfo)
        }
        if config.queueOfflineMessages {
            let store: OutboxStore = config.outboxStore
                ?? (config.persistOfflineMessages
                    ? FileOutboxStore(name: FileOutboxStore.name(apiKey: config.apiKey, userId: config.userId))
                    : MemoryOutboxStore())
            let sentSubject = messageSentSubject
            let failedSubject = messageFailedSubject
            self.outbox = Outbox(
                store: store,
                userId: config.userId,
                sender: { p in
                    try await api.sendMessage(
                        p.roomId,
                        senderUserId: p.senderUserId,
                        content: p.content,
                        type: p.type,
                        attachments: p.attachments,
                        metadata: p.metadata,
                        replyToId: p.replyToId,
                        clientMessageId: p.clientMessageId,
                        markTokenFailures: true
                    )
                },
                onSent: { sentSubject.send($0) },
                onFailed: { failedSubject.send($0) },
                now: now,
                sleep: sleep
            )
        } else {
            self.outbox = nil
        }
        self.apiService.onAuthError = { [weak self] event in
            self?.authErrorSubject.send(event)
        }
        if let outbox {
            connectionCancellable = realtimeService.connectionState.sink { state in
                if state == .connected { outbox.onConnected() }
            }
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
        try checkDisposed()
        try await realtimeService.connect()
    }

    /// Disconnect from the RiviumChat realtime server.
    public func disconnect() {
        guard !isDisposed else { return }
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
        guard !isDisposed else { return }
        realtimeService.subscribeRoom(roomId)
    }

    /// Subscribes only to a room's chat channel for messages/read receipts, without joining presence or typing.
    public func observeRoom(_ roomId: String) {
        guard !isDisposed else { return }
        realtimeService.observeRoom(roomId)
    }

    /// Unsubscribes from a room's realtime events.
    public func unsubscribeRoom(_ roomId: String) {
        guard !isDisposed else { return }
        realtimeService.unsubscribeRoom(roomId)
    }

    /// Leaves a room's presence and typing channels but keeps the chat channel for unread updates.
    public func leaveRoom(_ roomId: String) {
        guard !isDisposed else { return }
        realtimeService.leaveRoom(roomId)
    }

    /// Gets currently online users in a room.
    public func getRoomPresence(_ roomId: String) async throws -> Set<String> {
        try checkDisposed()
        return try await realtimeService.getRoomPresence(roomId)
    }

    /// Publishes a typing indicator.
    public func publishTyping(_ roomId: String) {
        guard !isDisposed else { return }
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
        try checkDisposed()
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
        try checkDisposed()
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
        try checkDisposed()
        return try await apiService.getRoomByExternalId(externalId)
    }

    /// Lists all rooms for the current user.
    public func listRooms() async throws -> [Room] {
        try checkDisposed()
        return try await apiService.listRooms(config.userId)
    }

    /// Gets a room by ID.
    public func getRoom(_ roomId: String) async throws -> Room {
        try checkDisposed()
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
        try checkDisposed()
        return try await apiService.addParticipant(roomId, externalUserId: externalUserId, displayName: displayName, locale: locale, role: role)
    }

    // MARK: - Message Operations

    /// Sends a message to a room.
    ///
    /// With ``RiviumChatConfig/queueOfflineMessages`` on, a send that fails
    /// because of the network is queued and returned as a pending message
    /// (`isPending == true`, id `local_<clientMessageId>`) instead of
    /// throwing; it is sent when the connection is back. Errors the server
    /// answers (not a member, invalid message, plan limit) still throw.
    public func sendMessage(
        _ roomId: String,
        content: String,
        type: MessageType = .text,
        attachments: [Attachment]? = nil,
        metadata: [String: Any]? = nil,
        replyToId: String? = nil
    ) async throws -> Message {
        try checkDisposed()
        if let outbox {
            return try await outbox.send(PendingMessage(
                clientMessageId: UUID().uuidString.lowercased(),
                roomId: roomId,
                senderUserId: config.userId,
                content: content,
                type: type,
                attachments: attachments,
                metadata: metadata,
                replyToId: replyToId,
                createdAt: now()
            ))
        }
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

    // MARK: - Offline outbox (queueOfflineMessages)

    /// Messages waiting to be sent, oldest first, as pending messages
    /// (`isPending == true`). Only `roomId`'s when given. Empty when
    /// ``RiviumChatConfig/queueOfflineMessages`` is off.
    public func getPendingMessages(roomId: String? = nil) -> [Message] {
        outbox?.pending(roomId: roomId).map { $0.toMessage() } ?? []
    }

    /// Tries to send the waiting messages now; returns when done or stopped
    /// by the network.
    public func retryPendingMessages() async {
        guard !isDisposed else { return }
        await outbox?.flush()
    }

    /// Removes a waiting message (`localId` = the pending message's id) from
    /// the queue. Emits nothing. Returns false when it is not queued (any
    /// more); a message already being sent cannot be recalled.
    @discardableResult
    public func cancelPendingMessage(_ localId: String) -> Bool {
        outbox?.cancel(localId) ?? false
    }

    /// Empties the queue, including a persistent store. Call it on sign-out
    /// when another user may sign in on this device.
    public func clearPendingMessages() {
        outbox?.clear()
    }

    /// Gets messages for a room with pagination.
    public func getMessages(
        _ roomId: String,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> PaginatedMessages {
        try checkDisposed()
        return try await apiService.getMessages(roomId, userId: config.userId, limit: limit, before: before)
    }

    /// Marks messages in a room as read.
    public func markAsRead(_ roomId: String) async throws {
        try checkDisposed()
        try await apiService.markAsRead(roomId, config.userId)
    }

    /// Deletes a message.
    public func deleteMessage(_ messageId: String) async throws {
        try checkDisposed()
        try await apiService.deleteMessage(messageId, config.userId)
    }

    /// Edits a message.
    public func editMessage(_ messageId: String, content: String) async throws -> Message {
        try checkDisposed()
        return try await apiService.editMessage(messageId, userId: config.userId, content: content)
    }

    /// Searches messages in a room.
    public func searchMessages(
        _ roomId: String,
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        try checkDisposed()
        return try await apiService.searchMessages(roomId, userId: config.userId, query: query, limit: limit, offset: offset)
    }

    /// Searches messages in a room and reports how many match in total.
    ///
    /// Same search as ``searchMessages(_:query:limit:offset:)``; the result
    /// also carries `total` (all matches, not only this page) and `hasMore`.
    ///
    /// ```swift
    /// let result = try await client.searchMessagesWithTotal(roomId, query: "Order #1001")
    /// print("\(result.total) matches")
    /// ```
    public func searchMessagesWithTotal(
        _ roomId: String,
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SearchResult {
        try checkDisposed()
        return try await apiService.searchMessagesWithTotal(roomId, userId: config.userId, query: query, limit: limit, offset: offset)
    }

    // MARK: - Reaction Operations

    /// Adds a reaction to a message.
    public func addReaction(_ messageId: String, emoji: String) async throws -> Reaction {
        try checkDisposed()
        return try await apiService.addReaction(messageId, userId: config.userId, emoji: emoji)
    }

    /// Removes a reaction from a message.
    public func removeReaction(_ messageId: String, emoji: String) async throws {
        try checkDisposed()
        try await apiService.removeReaction(messageId, userId: config.userId, emoji: emoji)
    }

    /// Gets all reactions for a message.
    public func getReactions(_ messageId: String) async throws -> [Reaction] {
        try checkDisposed()
        return try await apiService.getReactions(messageId)
    }

    // MARK: - Pin Operations

    /// Pins a message.
    public func pinMessage(_ messageId: String) async throws -> Message {
        try checkDisposed()
        return try await apiService.pinMessage(messageId, userId: config.userId)
    }

    /// Unpins a message.
    public func unpinMessage(_ messageId: String) async throws {
        try checkDisposed()
        try await apiService.unpinMessage(messageId, userId: config.userId)
    }

    /// Gets all pinned messages in a room.
    public func getPinnedMessages(_ roomId: String) async throws -> [Message] {
        try checkDisposed()
        return try await apiService.getPinnedMessages(roomId)
    }

    // MARK: - Other Operations

    /// Gets unread message summary for the current user.
    public func getUnreadSummary() async throws -> UnreadSummary {
        try checkDisposed()
        return try await apiService.getUnreadSummary(config.userId)
    }

    /// Gets messages where the current user was mentioned.
    public func getMentions(
        _ roomId: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        try checkDisposed()
        return try await apiService.getMentions(roomId, userId: config.userId, limit: limit, offset: offset)
    }

    // MARK: - Lifecycle

    /// Calls after ``dispose()`` throw instead of crashing the app. Calls that
    /// cannot throw do nothing.
    private func checkDisposed() throws {
        if isDisposed {
            throw RiviumChatClientDisposedError()
        }
    }

    /// Disposes all resources.
    public func dispose() {
        if isDisposed { return }
        isDisposed = true
        connectionCancellable?.cancel()
        outbox?.dispose()
        realtimeService.dispose()
        apiService.dispose()
    }
}
