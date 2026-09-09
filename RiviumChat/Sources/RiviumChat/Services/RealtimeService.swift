import Foundation
import Combine
import SwiftCentrifuge

/// Realtime service for RiviumChat using Centrifugo.
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
    /// Centrifuge's own registry. A screen that leaves a room and rejoins it
    /// across a lifecycle event drives both without synchronisation, and
    /// interleaving them leaves the registries disagreeing — which surfaces as
    /// "Subscription to a channel already exists in client's internal registry".
    private let channelLock = NSRecursiveLock()

    /// Tears one channel down: frees Centrifuge's registry entry *and*
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

    public init(_ config: RiviumChatConfig, _ getToken: @escaping () async throws -> String) {
        self.config = config
        self.getToken = getToken
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Connect to the Centrifugo server.
    /// Waits until the WebSocket connection is actually established before returning.
    public func connect() async throws {
        // Already connected
        if currentConnectionState == .connected {
            return
        }

        // Connection in progress — wait for it
        if client != nil && currentConnectionState == .connecting {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.additionalConnectContinuations.append(continuation)
            }
            return
        }

        guard client == nil else { return }

        connectionStateSubject.send(.connecting)

        let token = try await getToken()

        var clientConfig = CentrifugeClientConfig()
        clientConfig.token = token

        client = CentrifugeClient(
            endpoint: RiviumChatConfig.centrifugoUrl,
            config: clientConfig,
            delegate: self
        )

        // Wait for the onConnected or onError callback before returning
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.client?.connect()
        }
    }

    /// Disconnect from the Centrifugo server.
    public func disconnect() {
        // Free Centrifuge's registry as well as our own maps. Clearing only our
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
        guard let sub = subscriptions[channel] else { return [] }

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

    /// Publishes a typing indicator.
    private var lastTypingTime: TimeInterval = 0

    /// Publishes a typing indicator (throttled to 2 seconds).
    public func publishTyping(_ roomId: String) {
        let now = Date().timeIntervalSince1970
        guard now - lastTypingTime >= 2.0 else { return }
        lastTypingTime = now

        let channel = "typing:room_\(roomId)"
        guard let sub = subscriptions[channel] else { return }

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
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let readAt = formatter.date(from: readAtString) ?? ISO8601DateFormatter().date(from: readAtString) ?? Date()
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
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let editedAt = fmt.date(from: editedAtString) ?? ISO8601DateFormatter().date(from: editedAtString) ?? Date()
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
        connectContinuation?.resume()
        connectContinuation = nil
        for continuation in additionalConnectContinuations {
            continuation.resume()
        }
        additionalConnectContinuations.removeAll()

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
        if let continuation = connectContinuation {
            continuation.resume(throwing: RiviumChatError.connectionError(event.error))
            connectContinuation = nil
        }
        for continuation in additionalConnectContinuations {
            continuation.resume(throwing: RiviumChatError.connectionError(event.error))
        }
        additionalConnectContinuations.removeAll()
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
        service?.markUnsubscribed(channel)
        DispatchQueue.main.async {
            self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: self.roomId,
                channel: self.channel,
                status: .unsubscribed,
                code: Int(event.code),
                reason: event.reason
            ))
        }
    }

    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        // Drop the dead subscription so the next subscribe builds a fresh one
        // instead of short-circuiting on a stale entry.
        service?.markUnsubscribed(channel, removeFromClient: true)
        DispatchQueue.main.async {
            self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: self.roomId,
                channel: self.channel,
                status: .error,
                reason: event.error.localizedDescription
            ))
            self.service?.errorSubject.send(ConnectionErrorEvent(
                error: "Subscription failed on \(self.channel): \(event.error.localizedDescription)"
            ))
            self.service?.recoveryFailedSubject.send(self.roomId)
        }
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
        service?.markUnsubscribed(channel)
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .unsubscribed)) }
    }

    // Without this a rejected subscribe was invisible: the channel never went
    // live, nothing was raised, and the room looked fine while presence or
    // typing silently never arrived.
    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        service?.markUnsubscribed(channel, removeFromClient: true)
        DispatchQueue.main.async {
            self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: self.roomId,
                channel: self.channel,
                status: .error,
                reason: event.error.localizedDescription
            ))
            self.service?.errorSubject.send(ConnectionErrorEvent(
                error: "Subscription failed on \(self.channel): \(event.error.localizedDescription)"
            ))
        }
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
        service?.markUnsubscribed(channel)
        DispatchQueue.main.async { self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(roomId: self.roomId, channel: self.channel, status: .unsubscribed)) }
    }

    // Without this a rejected subscribe was invisible: the channel never went
    // live, nothing was raised, and the room looked fine while presence or
    // typing silently never arrived.
    func onError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscriptionErrorEvent) {
        service?.markUnsubscribed(channel, removeFromClient: true)
        DispatchQueue.main.async {
            self.service?.subscriptionStateSubject.send(SubscriptionStateEvent(
                roomId: self.roomId,
                channel: self.channel,
                status: .error,
                reason: event.error.localizedDescription
            ))
            self.service?.errorSubject.send(ConnectionErrorEvent(
                error: "Subscription failed on \(self.channel): \(event.error.localizedDescription)"
            ))
        }
    }

    func onJoin(_ sub: CentrifugeSubscription, _ event: CentrifugeJoinEvent) {
        service?.handlePresenceJoin(roomId: roomId, userId: event.user)
    }

    func onLeave(_ sub: CentrifugeSubscription, _ event: CentrifugeLeaveEvent) {
        service?.handlePresenceLeave(roomId: roomId, userId: event.user)
    }
}
