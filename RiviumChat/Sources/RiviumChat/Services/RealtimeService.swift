import Foundation
import Combine
import SwiftCentrifuge

/// Realtime service for RiviumChat.
public class RealtimeService {
    private let config: RiviumChatConfig
    private let getToken: () async throws -> String
    private var client: CentrifugeClient?
    private var subscriptions: [String: CentrifugeSubscription] = [:]
    private var delegates: [String: CentrifugeSubscriptionDelegate] = [:]

    /// Channels confirmed subscribed by the server. A channel in
    /// `subscriptions` but missing here was created and never confirmed, and
    /// must not be treated as usable — otherwise a rejected subscribe leaves
    /// the room silently realtime-dead.
    private var subscribedChannels: Set<String> = []

    /// Guards the three collections above.
    ///
    /// Subscribe and unsubscribe hand a channel name back and forth with
    /// the realtime client's own registry. A screen that leaves a room and rejoins it
    /// across a lifecycle event drives both without synchronisation, and
    /// interleaving them leaves the registries disagreeing — which surfaces as
    /// "Subscription to a channel already exists in client's internal registry".
    private let channelLock = NSRecursiveLock()

    /// Tears one channel down: frees the realtime client's registry entry *and*
    /// unsubscribes. The previous version removed the subscription from the
    /// client without ever calling `unsubscribe()`, leaving the server to
    /// believe the client was still subscribed.
    private func teardownChannel(_ channel: String) {
        channelLock.lock()
        defer { channelLock.unlock() }

        subscribedChannels.remove(channel)
        delegates.removeValue(forKey: channel)
        guard let sub = subscriptions.removeValue(forKey: channel) else { return }
        client?.removeSubscription(sub)
        sub.unsubscribe()
    }

    /// Whether a new subscription should be built for `channel`. A stale,
    /// never-confirmed subscription is torn down first — returning early on
    /// one is what made subscribeRoom report success on a dead channel.
    private func shouldSubscribe(_ channel: String) -> Bool {
        channelLock.lock()
        defer { channelLock.unlock() }

        if subscribedChannels.contains(channel) { return false }
        if subscriptions[channel] != nil { teardownChannel(channel) }
        return true
    }

    /// Marks a channel live. Called from the subscription delegates.
    func markSubscribed(_ channel: String) {
        channelLock.lock(); defer { channelLock.unlock() }
        subscribedChannels.insert(channel)
    }

    /// Marks a channel not live, dropping it so a retry rebuilds it.
    func markUnsubscribed(_ channel: String, removeFromClient: Bool = false) {
        channelLock.lock(); defer { channelLock.unlock() }
        subscribedChannels.remove(channel)
        if removeFromClient, let sub = subscriptions.removeValue(forKey: channel) {
            client?.removeSubscription(sub)
            delegates.removeValue(forKey: channel)
        }
    }

    /// Whether every channel of `roomId` is currently subscribed.
    public func isRoomSubscribed(_ roomId: String) -> Bool {
        channelLock.lock(); defer { channelLock.unlock() }
        return subscribedChannels.isSuperset(of: [
            "chat:room_\(roomId)", "presence:room_\(roomId)", "typing:room_\(roomId)"
        ])
    }

    /// Channels of `roomId` currently subscribed.
    public func subscribedChannelsFor(_ roomId: String) -> Set<String> {
        channelLock.lock(); defer { channelLock.unlock() }
        return subscribedChannels.intersection([
            "chat:room_\(roomId)", "presence:room_\(roomId)", "typing:room_\(roomId)"
        ])
    }
    private var pendingRoomSubscriptions: [String] = []
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private let decoder: JSONDecoder

    // Connection state
    private let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    public var connectionState: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    public var currentConnectionState: ConnectionState {
        connectionStateSubject.value
    }
    private var additionalConnectContinuations: [CheckedContinuation<Void, Error>] = []

    /// Guards the connect() continuations: they are resumed from the realtime client's
    /// queue and from disconnect(), and resuming one twice crashes the app.
    private let continuationLock = NSLock()

    /// Takes every waiting connect() continuation, so each is resumed once.
    private func takeConnectContinuations() -> [CheckedContinuation<Void, Error>] {
        continuationLock.lock(); defer { continuationLock.unlock() }
        let waiting = [connectContinuation].compactMap { $0 } + additionalConnectContinuations
        connectContinuation = nil
        additionalConnectContinuations.removeAll()
        return waiting
    }

    // Event publishers — all deliver on main thread for SwiftUI compatibility
    private let messageSubject = PassthroughSubject<Message, Never>()
    public var onMessage: AnyPublisher<Message, Never> {
        messageSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let readReceiptSubject = PassthroughSubject<ReadReceipt, Never>()
    public var onReadReceipt: AnyPublisher<ReadReceipt, Never> {
        readReceiptSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let deletionSubject = PassthroughSubject<MessageDeletion, Never>()
    public var onMessageDeleted: AnyPublisher<MessageDeletion, Never> {
        deletionSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let typingSubject = PassthroughSubject<TypingEvent, Never>()
    public var onTypingEvent: AnyPublisher<TypingEvent, Never> {
        typingSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let presenceSubject = PassthroughSubject<PresenceEvent, Never>()
    public var onPresenceChange: AnyPublisher<PresenceEvent, Never> {
        presenceSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let reactionSubject = PassthroughSubject<ReactionEvent, Never>()
    public var onReactionEvent: AnyPublisher<ReactionEvent, Never> {
        reactionSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let editSubject = PassthroughSubject<MessageEditEvent, Never>()
    public var onMessageEdited: AnyPublisher<MessageEditEvent, Never> {
        editSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let pinSubject = PassthroughSubject<MessagePinEvent, Never>()
    public var onMessagePinChanged: AnyPublisher<MessagePinEvent, Never> {
        pinSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    fileprivate let errorSubject = PassthroughSubject<ConnectionErrorEvent, Never>()
    public var onConnectionError: AnyPublisher<ConnectionErrorEvent, Never> {
        errorSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    fileprivate let subscriptionStateSubject = PassthroughSubject<SubscriptionStateEvent, Never>()
    public var onSubscriptionState: AnyPublisher<SubscriptionStateEvent, Never> {
        subscriptionStateSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    fileprivate let recoveryFailedSubject = PassthroughSubject<String, Never>()
    public var onRecoveryFailed: AnyPublisher<String, Never> {
        recoveryFailedSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// Whether a realtime client (a socket) exists.
    var hasClient: Bool { client != nil }

    /// Bumped by ``disconnect()``. A ``connect()`` still fetching its token
    /// when the app disconnected (or disposed) must not open a socket after.
    private var generation = 0

    /// The server's code and reason behind a subscription error, when it sent
    /// one (for example 403, `Not a participant in this room`).
    static func subscriptionFailure(_ error: Error) -> (code: Int?, reason: String) {
        switch error {
        case CentrifugeError.replyError(let code, let message, _):
            return (Int(code), message)
        case CentrifugeError.subscriptionSubscribeError(let inner),
             CentrifugeError.subscriptionTokenError(let inner),
             CentrifugeError.subscriptionRefreshError(let inner):
            return subscriptionFailure(inner)
        default:
            return (nil, String(describing: error))
        }
    }

    /// Unsubscribe codes the realtime client sets itself (0 = unsubscribe called,
    /// 2 = client closed). Every other code means the server refused or ended
    /// the subscription.
    static func isServerUnsubscribe(_ code: UInt32) -> Bool {
        code != 0 && code != 2
    }

    /// A channel's subscription ended. When the server refused or ended it
    /// (for example: not a participant of the room) the dead subscription is
    /// dropped so a later subscribe builds a fresh one, and for the chat
    /// channel the app hears `onRecoveryFailed`: the room's live updates
    /// stopped, so it should reload or show the refusal.
    func handleUnsubscribed(roomId: String, channel: String, code: UInt32, reason: String) {
        let refused = Self.isServerUnsubscribe(code)
        markUnsubscribed(channel, removeFromClient: refused)
        DispatchQueue.main.async {
            self.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: roomId,
                channel: channel,
                status: .unsubscribed,
                code: Int(code),
                reason: reason
            ))
            guard refused else { return }
            self.errorSubject.send(ConnectionErrorEvent(error: "Subscription refused on \(channel): \(reason)"))
            if channel.hasPrefix("chat:") {
                self.recoveryFailedSubject.send(roomId)
            }
        }
    }

    /// A channel's subscribe failed (the realtime client retries temporary errors).
    func handleSubscriptionError(roomId: String, channel: String, error: Error) {
        markUnsubscribed(channel, removeFromClient: true)
        let failure = Self.subscriptionFailure(error)
        DispatchQueue.main.async {
            self.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: roomId,
                channel: channel,
                status: .error,
                code: failure.code,
                reason: failure.reason
            ))
            self.errorSubject.send(ConnectionErrorEvent(
                error: "Subscription failed on \(channel): \(failure.reason)"
            ))
            if channel.hasPrefix("chat:") {
                self.recoveryFailedSubject.send(roomId)
            }
        }
    }

    public init(_ config: RiviumChatConfig, _ getToken: @escaping () async throws -> String) {
        self.config = config
        self.getToken = getToken
        self.decoder = RiviumChatJSON.decoder()
    }

    /// Connect to the realtime server.
    /// Waits until the WebSocket connection is actually established before returning.
    public func connect() async throws {
        // Already connected
        if currentConnectionState == .connected {
            return
        }

        // Connection in progress — wait for it
        if client != nil && currentConnectionState == .connecting {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuationLock.lock()
                self.additionalConnectContinuations.append(continuation)
                self.continuationLock.unlock()
            }
            return
        }

        guard client == nil else { return }

        let attempt = generation
        connectionStateSubject.send(.connecting)

        let token: String
        do {
            token = try await getToken()
        } catch {
            // disconnect() ran meanwhile: it already set the state.
            guard attempt == generation else { throw CancellationError() }
            // No connection without a token (unknown key, token required,
            // API unreachable, tokenProvider failed): report it like any
            // connection error. Without this the state stayed "connecting".
            connectionStateSubject.send(.error)
            DispatchQueue.main.async {
                self.errorSubject.send(ConnectionErrorEvent(error: error))
            }
            throw error
        }

        // disconnect() or dispose() ran while the token was being fetched:
        // the app asked to be offline, so open no socket.
        guard attempt == generation, client == nil else { throw CancellationError() }

        var clientConfig = CentrifugeClientConfig()
        clientConfig.token = token
        // Asked again whenever the token expires or is rejected, so a
        // long-lived connection survives token expiry.
        clientConfig.tokenGetter = connectionTokenGetter()

        client = CentrifugeClient(
            endpoint: RiviumChatConfig.realtimeUrl,
            config: clientConfig,
            delegate: self
        )

        // Wait for the onConnected or onError callback before returning
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuationLock.lock()
            self.connectContinuation = continuation
            self.continuationLock.unlock()
            self.client?.connect()
        }
    }

    /// Fetches a fresh connection token from the same source as the first
    /// one. Calls `completion` exactly once, as the realtime client requires.
    func connectionTokenGetter() -> CentrifugeConnectionTokenGetter {
        let getToken = self.getToken
        return { _, completion in
            Task {
                do {
                    completion(.success(try await getToken()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Disconnect from the realtime server.
    public func disconnect() {
        generation += 1
        // Free the realtime client's registry as well as our own maps. Clearing only our
        // maps left every channel name held by the client, so each one threw
        // "already exists" on the next subscribe for the life of the process.
        channelLock.lock()
        for channel in subscriptions.keys { teardownChannel(channel) }
        subscriptions.removeAll()
        delegates.removeAll()
        subscribedChannels.removeAll()
        channelLock.unlock()

        client?.disconnect()
        client = nil
        connectionStateSubject.send(.disconnected)

        // A connect() still waiting for the socket would wait forever (and
        // leak its continuation): it ends with a cancellation instead.
        for continuation in takeConnectContinuations() {
            continuation.resume(throwing: CancellationError())
        }
    }

    /// Drops the current connection and opens a new one.
    ///
    /// `connect()` returns early while a client exists, leaving a host no way
    /// to recover a socket it believes is stale after a long background.
    public func reconnect() async throws {
        disconnect()
        try await connect()
    }

    /// Subscribe only to a room's chat channel (messages, read receipts) without presence/typing.
    public func observeRoom(_ roomId: String) {
        guard let client = client else { return }

        // The delegates mutate the same maps from the realtime client's queue.
        channelLock.lock()
        defer { channelLock.unlock() }
        do {
            let chatChannel = "chat:room_\(roomId)"
            if shouldSubscribe(chatChannel) {
                let chatDelegate = ChatChannelDelegate(roomId: roomId, service: self)
                let sub = try client.newSubscription(channel: chatChannel, delegate: chatDelegate)
                delegates[chatChannel] = chatDelegate
                sub.subscribe()
                subscriptions[chatChannel] = sub
            }
        } catch {
            // Ignore subscription creation errors
        }
    }

    /// Subscribe to a room's channels.
    public func subscribeRoom(_ roomId: String) {
        guard let client = client else {
            if !pendingRoomSubscriptions.contains(roomId) {
                pendingRoomSubscriptions.append(roomId)
            }
            return
        }

        // The delegates mutate the same maps from the realtime client's queue.
        channelLock.lock()
        defer { channelLock.unlock() }
        do {
            // Chat channel (messages, read receipts, etc.) — recoverable
            let chatChannel = "chat:room_\(roomId)"
            if shouldSubscribe(chatChannel) {
                let chatDelegate = ChatChannelDelegate(roomId: roomId, service: self)
                let sub = try client.newSubscription(channel: chatChannel, delegate: chatDelegate)
                delegates[chatChannel] = chatDelegate
                sub.subscribe()
                subscriptions[chatChannel] = sub
            }

            // Presence channel
            let presenceChannel = "presence:room_\(roomId)"
            if shouldSubscribe(presenceChannel) {
                let presenceDelegate = PresenceChannelDelegate(roomId: roomId, service: self)
                let sub = try client.newSubscription(channel: presenceChannel, delegate: presenceDelegate)
                delegates[presenceChannel] = presenceDelegate
                sub.subscribe()
                subscriptions[presenceChannel] = sub
            }

            // Typing channel
            let typingChannel = "typing:room_\(roomId)"
            if shouldSubscribe(typingChannel) {
                let typingDelegate = TypingChannelDelegate(roomId: roomId, config: config, service: self)
                let sub = try client.newSubscription(channel: typingChannel, delegate: typingDelegate)
                delegates[typingChannel] = typingDelegate
                sub.subscribe()
                subscriptions[typingChannel] = sub
            }
        } catch {
            // Ignore subscription creation errors
        }
    }

    /// Unsubscribe from a room's channels.
    public func unsubscribeRoom(_ roomId: String) {
        let channels = [
            "chat:room_\(roomId)",
            "presence:room_\(roomId)",
            "typing:room_\(roomId)"
        ]
        for channel in channels { teardownChannel(channel) }
    }

    /// Unsubscribe only from presence and typing channels (keeps chat channel for unread updates).
    public func leaveRoom(_ roomId: String) {
        let channels = [
            "presence:room_\(roomId)",
            "typing:room_\(roomId)"
        ]
        for channel in channels { teardownChannel(channel) }
    }

    /// Gets currently online users in a room.
    public func getRoomPresence(_ roomId: String) async throws -> Set<String> {
        let channel = "presence:room_\(roomId)"
        channelLock.lock()
        let subscription = subscriptions[channel]
        channelLock.unlock()
        guard let sub = subscription else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            sub.presence { result in
                switch result {
                case .success(let presenceResult):
                    let users = Set(presenceResult.presence.compactMap { (_, info) -> String? in
                        let user = info.user
                        return user.isEmpty ? nil : user
                    })
                    continuation.resume(returning: users)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Last typing publish per room, so typing in one room never mutes another.
    private var lastTypingTimes: [String: TimeInterval] = [:]
    private let typingLock = NSLock()

    /// Throttles typing to one publish every 2 seconds for each room.
    func shouldPublishTyping(_ roomId: String, now: TimeInterval) -> Bool {
        typingLock.lock(); defer { typingLock.unlock() }
        if let last = lastTypingTimes[roomId], now - last < 2.0 { return false }
        lastTypingTimes[roomId] = now
        return true
    }

    /// Publishes a typing indicator (throttled to 2 seconds per room).
    public func publishTyping(_ roomId: String) {
        let channel = "typing:room_\(roomId)"
        channelLock.lock()
        let subscription = subscriptions[channel]
        channelLock.unlock()
        guard let sub = subscription else { return }
        guard shouldPublishTyping(roomId, now: Date().timeIntervalSince1970) else { return }

        let payload: [String: Any] = [
            "userId": config.userId,
            "isTyping": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        sub.publish(data: data) { _ in
            // Ignore result
        }
    }

    /// Disposes all resources.
    public func dispose() {
        disconnect()
    }

    // MARK: - Event Handlers

    fileprivate func handleChatPublication(roomId: String, data: Data) {
        // Parse on background thread, then dispatch events on main thread
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            // Backend sends 'event' field, but also support 'type' for backwards compatibility
            let eventType = json["event"] as? String ?? json["type"] as? String
            let payload = json["data"] as? [String: Any] ?? json

            switch eventType {
            case "message":
                let messageData = try JSONSerialization.data(withJSONObject: payload)
                let message = try decoder.decode(Message.self, from: messageData)
                DispatchQueue.main.async { self.messageSubject.send(message) }

            case "read":
                if let userId = payload["userId"] as? String,
                   let readAtString = payload["readAt"] as? String {
                    let readAt = RiviumChatJSON.parseDate(readAtString) ?? Date()
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.readReceiptSubject.send(ReadReceipt(userId: userId, roomId: roomId, readAt: readAt)) }
                }

            case "deleted":
                if let messageId = payload["messageId"] as? String,
                   let deletedBy = payload["deletedBy"] as? String {
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.deletionSubject.send(MessageDeletion(messageId: messageId, roomId: roomId, deletedBy: deletedBy)) }
                }

            case "message_edited":
                if let messageId = payload["messageId"] as? String,
                   let content = payload["content"] as? String,
                   let editedBy = payload["editedBy"] as? String,
                   let editedAtString = payload["editedAt"] as? String {
                    let editedAt = RiviumChatJSON.parseDate(editedAtString) ?? Date()
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.editSubject.send(MessageEditEvent(messageId: messageId, roomId: roomId, content: content, editedBy: editedBy, editedAt: editedAt)) }
                }

            case "reaction_added":
                if let messageId = payload["messageId"] as? String,
                   let userId = payload["userId"] as? String,
                   let emoji = payload["emoji"] as? String {
                    let roomId = payload["roomId"] as? String ?? roomId
                    let reactionId = payload["reactionId"] as? String
                    DispatchQueue.main.async { self.reactionSubject.send(ReactionEvent(messageId: messageId, roomId: roomId, userId: userId, emoji: emoji, added: true, reactionId: reactionId)) }
                }

            case "reaction_removed":
                if let messageId = payload["messageId"] as? String,
                   let userId = payload["userId"] as? String,
                   let emoji = payload["emoji"] as? String {
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.reactionSubject.send(ReactionEvent(messageId: messageId, roomId: roomId, userId: userId, emoji: emoji, added: false)) }
                }

            case "message_pinned":
                if let messageId = payload["messageId"] as? String,
                   let userId = payload["pinnedBy"] as? String {
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.pinSubject.send(MessagePinEvent(messageId: messageId, roomId: roomId, userId: userId, pinned: true)) }
                }

            case "message_unpinned":
                if let messageId = payload["messageId"] as? String,
                   let userId = payload["unpinnedBy"] as? String {
                    let roomId = payload["roomId"] as? String ?? roomId
                    DispatchQueue.main.async { self.pinSubject.send(MessagePinEvent(messageId: messageId, roomId: roomId, userId: userId, pinned: false)) }
                }

            default:
                // Try parsing as a direct message if no type specified
                if payload["id"] != nil && payload["content"] != nil {
                    let messageData = try JSONSerialization.data(withJSONObject: payload)
                    let message = try decoder.decode(Message.self, from: messageData)
                    DispatchQueue.main.async { self.messageSubject.send(message) }
                }
            }
        } catch {
            // Ignore malformed publications
        }
    }

    fileprivate func handleTypingPublication(roomId: String, data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let userId = json["userId"] as? String else { return }
            // Filter out own typing events
            guard userId != config.userId else { return }
            let isTyping = json["isTyping"] as? Bool ?? true
            DispatchQueue.main.async { self.typingSubject.send(TypingEvent(roomId: roomId, userId: userId, isTyping: isTyping)) }
        } catch {
            // Ignore parsing error
        }
    }

    fileprivate func handlePresenceJoin(roomId: String, userId: String) {
        guard !userId.isEmpty else { return }
        DispatchQueue.main.async { self.presenceSubject.send(PresenceEvent(roomId: roomId, userId: userId, isOnline: true)) }
    }

    fileprivate func handlePresenceLeave(roomId: String, userId: String) {
        guard !userId.isEmpty else { return }
        DispatchQueue.main.async { self.presenceSubject.send(PresenceEvent(roomId: roomId, userId: userId, isOnline: false)) }
    }
}

// MARK: - CentrifugeClientDelegate

extension RealtimeService: CentrifugeClientDelegate {
    public func onConnecting(_ client: CentrifugeClient, _ event: CentrifugeConnectingEvent) {
        DispatchQueue.main.async { self.connectionStateSubject.send(.connecting) }
    }

    public func onConnected(_ client: CentrifugeClient, _ event: CentrifugeConnectedEvent) {
        DispatchQueue.main.async { self.connectionStateSubject.send(.connected) }

        // Resume connect() awaiters
        for continuation in takeConnectContinuations() {
            continuation.resume()
        }

        // Process any pending room subscriptions
        let pending = pendingRoomSubscriptions
        pendingRoomSubscriptions.removeAll()
        for roomId in pending {
            subscribeRoom(roomId)
        }
    }

    public func onDisconnected(_ client: CentrifugeClient, _ event: CentrifugeDisconnectedEvent) {
        DispatchQueue.main.async {
            self.connectionStateSubject.send(.disconnected)
            if !event.reason.isEmpty {
                self.errorSubject.send(ConnectionErrorEvent(error: "Disconnected: \(event.reason)"))
            }
        }
    }

    public func onError(_ client: CentrifugeClient, _ event: CentrifugeErrorEvent) {
        DispatchQueue.main.async {
            self.connectionStateSubject.send(.error)
            self.errorSubject.send(ConnectionErrorEvent(error: event.error))
        }

        // Resume connect() awaiters with error if still waiting
        for continuation in takeConnectContinuations() {
            continuation.resume(throwing: RiviumChatError.connectionError(event.error))
        }
    }
}

// MARK: - Channel Delegates

private class ChatChannelDelegate: CentrifugeSubscriptionDelegate {
    let roomId: String
    let channel: String
    weak var service: RealtimeService?

    init(roomId: String, service: RealtimeService) {
        self.roomId = roomId
        self.channel = "chat:room_\(roomId)"
        self.service = service
    }

    func onSubscribing(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribingEvent) {
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribing)) }
    }

    func onSubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribedEvent) {
        service?.markSubscribed(channel)
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribed)) }

        // Check for recovery failure
        if event.wasRecovering && !event.recovered {
            DispatchQueue.main.async { self.service?.recoveryFailedSubject.send(self.roomId) }
        }
    }

    func onUnsubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeUnsubscribedEvent) {
        service?.handleUnsubscribed(roomId: roomId, channel: channel, code: event.code, reason: event.reason)
    }

    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        // Drop the dead subscription so the next subscribe builds a fresh one
        // instead of short-circuiting on a stale entry.
        service?.handleSubscriptionError(roomId: roomId, channel: channel, error: event.error)
    }

    func onPublication(_ sub: CentrifugeSubscription, _ event: CentrifugePublicationEvent) {
        service?.handleChatPublication(roomId: roomId, data: event.data)
    }
}

private class TypingChannelDelegate: CentrifugeSubscriptionDelegate {
    let roomId: String
    let channel: String
    let config: RiviumChatConfig
    weak var service: RealtimeService?

    init(roomId: String, config: RiviumChatConfig, service: RealtimeService) {
        self.roomId = roomId
        self.channel = "typing:room_\(roomId)"
        self.config = config
        self.service = service
    }

    func onSubscribing(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribingEvent) {
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribing)) }
    }

    func onSubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribedEvent) {
        service?.markSubscribed(channel)
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribed)) }
    }

    func onUnsubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeUnsubscribedEvent) {
        service?.handleUnsubscribed(roomId: roomId, channel: channel, code: event.code, reason: event.reason)
    }

    // Without this a rejected subscribe was invisible: the channel never went
    // live, nothing was raised, and the room looked fine while presence or
    // typing silently never arrived.
    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        service?.handleSubscriptionError(roomId: roomId, channel: channel, error: event.error)
    }

    func onPublication(_ sub: CentrifugeSubscription, _ event: CentrifugePublicationEvent) {
        service?.handleTypingPublication(roomId: roomId, data: event.data)
    }
}

private class PresenceChannelDelegate: CentrifugeSubscriptionDelegate {
    let roomId: String
    let channel: String
    weak var service: RealtimeService?

    init(roomId: String, service: RealtimeService) {
        self.roomId = roomId
        self.channel = "presence:room_\(roomId)"
        self.service = service
    }

    func onSubscribing(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribingEvent) {
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribing)) }
    }

    func onSubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribedEvent) {
        service?.markSubscribed(channel)
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .subscribed)) }

        // Query current presence and emit events for all online users.
        // This ensures we detect users who joined before we subscribed.
        sub.presence { [weak self] result in
            guard let self = self else { return }
            if case .success(let presenceResult) = result {
                for (_, info) in presenceResult.presence {
                    if !info.user.isEmpty {
                        self.service?.handlePresenceJoin(roomId: self.roomId, userId: info.user)
                    }
                }
            }
        }
    }

    func onUnsubscribed(_ sub: CentrifugeSubscription, _ event: CentrifugeUnsubscribedEvent) {
        service?.handleUnsubscribed(roomId: roomId, channel: channel, code: event.code, reason: event.reason)
    }

    // Without this a rejected subscribe was invisible: the channel never went
    // live, nothing was raised, and the room looked fine while presence or
    // typing silently never arrived.
    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        service?.handleSubscriptionError(roomId: roomId, channel: channel, error: event.error)
    }

    func onJoin(_ sub: CentrifugeSubscription, _ event: CentrifugeJoinEvent) {
        service?.handlePresenceJoin(roomId: roomId, userId: event.user)
    }

    func onLeave(_ sub: CentrifugeSubscription, _ event: CentrifugeLeaveEvent) {
        service?.handlePresenceLeave(roomId: roomId, userId: event.user)
    }
}
