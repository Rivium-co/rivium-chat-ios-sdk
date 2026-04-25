import SwiftUI
import Combine
import RiviumChat

/// State holder for a chat channel/room
@MainActor
public final class ChatChannelState: ObservableObject {
    /// The room ID
    public let roomId: String

    /// Current user ID
    public let currentUserId: String

    /// Messages list (newest first)
    @Published public private(set) var messages: [Message] = []

    /// Whether more messages can be loaded
    @Published public private(set) var hasMore = true

    /// Whether currently loading more messages
    @Published public private(set) var isLoadingMore = false

    /// Whether initial load is in progress
    @Published public private(set) var isInitialLoading = true

    /// Users currently typing (excluding current user)
    @Published public private(set) var typingUsers: [String] = []

    /// Online users in the room
    @Published public private(set) var onlineUsers: Set<String> = []

    /// Other user's last read timestamp (for read receipts)
    @Published public private(set) var otherUserLastRead: Date?

    /// Message being replied to
    @Published public var replyingTo: Message?

    /// Current error state
    @Published public private(set) var error: Error?

    private let client: RiviumChatClient
    private var cancellables = Set<AnyCancellable>()
    private var typingTimers: [String: Timer] = [:]
    private var lastTypingTime: Date = .distantPast

    public init(client: RiviumChatClient, roomId: String, currentUserId: String) {
        self.client = client
        self.roomId = roomId
        self.currentUserId = currentUserId
    }

    /// Initialize the channel by subscribing and loading messages
    public func initialize() async {
        do {
            // Subscribe to room events
            client.subscribeRoom(roomId)

            // Load initial messages
            let result = try await client.getMessages(roomId, limit: 50)
            messages = result.messages.reversed() // Newest first
            hasMore = result.messages.count >= 50

            // Get initial presence
            do {
                let presence = try await client.getRoomPresence(roomId)
                onlineUsers = Set(presence)
            } catch {
                // Presence fetch failed, continue anyway
            }

            // Load initial read state from room participants
            do {
                let room = try await client.getRoom(roomId)
                let otherParticipant = room.participants.first {
                    $0.externalUserId != currentUserId
                }
                if let lastRead = otherParticipant?.lastReadAt {
                    otherUserLastRead = lastRead
                }
            } catch {
                // Non-critical: read receipts will still work via real-time events
            }

            isInitialLoading = false
            self.error = nil

            // Start collecting events
            startEventCollection()

        } catch {
            self.error = error
            isInitialLoading = false
        }
    }

    /// Load more (older) messages
    public func loadMore() async {
        guard !isLoadingMore && hasMore && !messages.isEmpty else { return }

        isLoadingMore = true
        do {
            let oldestMessage = messages.last
            let result = try await client.getMessages(
                roomId,
                limit: 50,
                before: oldestMessage?.id
            )
            messages.append(contentsOf: result.messages.reversed())
            hasMore = result.messages.count >= 50
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }

    /// Send a new message
    public func sendMessage(content: String, attachments: [Attachment]? = nil) async {
        // Create pending message for optimistic update
        let pendingId = "pending_\(UUID().uuidString)"
        let pendingMessage = Message(
            id: pendingId,
            roomId: roomId,
            senderUserId: currentUserId,
            content: content,
            type: .text,
            attachments: attachments ?? [],
            metadata: nil,
            replyToId: replyingTo?.id,
            replyTo: replyingTo,
            isDeleted: false,
            createdAt: Date(),
            isEdited: false,
            editedAt: nil,
            editHistory: nil,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            reactions: [],
            isPending: true,
            isFailed: false
        )

        // Add to top of list (newest first)
        messages.insert(pendingMessage, at: 0)

        // Clear reply state
        let replyId = replyingTo?.id
        replyingTo = nil

        do {
            let sentMessage = try await client.sendMessage(
                roomId,
                content: content,
                attachments: attachments,
                replyToId: replyId
            )

            // Replace pending message with real one
            if let index = messages.firstIndex(where: { $0.id == pendingId }) {
                messages[index] = sentMessage
            }
        } catch {
            // Mark as failed
            if let index = messages.firstIndex(where: { $0.id == pendingId }) {
                messages[index] = Message(
                    id: pendingMessage.id,
                    roomId: pendingMessage.roomId,
                    senderUserId: pendingMessage.senderUserId,
                    content: pendingMessage.content,
                    type: pendingMessage.type,
                    attachments: pendingMessage.attachments,
                    metadata: pendingMessage.metadata,
                    replyToId: pendingMessage.replyToId,
                    replyTo: pendingMessage.replyTo,
                    isDeleted: pendingMessage.isDeleted,
                    createdAt: pendingMessage.createdAt,
                    isEdited: pendingMessage.isEdited,
                    editedAt: pendingMessage.editedAt,
                    editHistory: pendingMessage.editHistory,
                    isPinned: pendingMessage.isPinned,
                    pinnedAt: pendingMessage.pinnedAt,
                    pinnedBy: pendingMessage.pinnedBy,
                    reactions: pendingMessage.reactions,
                    isPending: false,
                    isFailed: true
                )
            }
        }
    }

    /// Retry sending a failed message
    public func retryMessage(messageId: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].isFailed else { return }

        let message = messages[index]

        // Mark as pending again
        messages[index] = Message(
            id: message.id,
            roomId: message.roomId,
            senderUserId: message.senderUserId,
            content: message.content,
            type: message.type,
            attachments: message.attachments,
            metadata: message.metadata,
            replyToId: message.replyToId,
            replyTo: message.replyTo,
            isDeleted: message.isDeleted,
            createdAt: message.createdAt,
            isEdited: message.isEdited,
            editedAt: message.editedAt,
            editHistory: message.editHistory,
            isPinned: message.isPinned,
            pinnedAt: message.pinnedAt,
            pinnedBy: message.pinnedBy,
            reactions: message.reactions,
            isPending: true,
            isFailed: false
        )

        do {
            let sentMessage = try await client.sendMessage(
                roomId,
                content: message.content,
                attachments: (message.attachments ?? []).isEmpty ? nil : message.attachments,
                replyToId: message.replyToId
            )

            if let newIndex = messages.firstIndex(where: { $0.id == messageId }) {
                messages[newIndex] = sentMessage
            }
        } catch {
            if let newIndex = messages.firstIndex(where: { $0.id == messageId }) {
                messages[newIndex] = Message(
                    id: message.id,
                    roomId: message.roomId,
                    senderUserId: message.senderUserId,
                    content: message.content,
                    type: message.type,
                    attachments: message.attachments,
                    metadata: message.metadata,
                    replyToId: message.replyToId,
                    replyTo: message.replyTo,
                    isDeleted: message.isDeleted,
                    createdAt: message.createdAt,
                    isEdited: message.isEdited,
                    editedAt: message.editedAt,
                    editHistory: message.editHistory,
                    isPinned: message.isPinned,
                    pinnedAt: message.pinnedAt,
                    pinnedBy: message.pinnedBy,
                    reactions: message.reactions,
                    isPending: false,
                    isFailed: true
                )
            }
        }
    }

    /// Delete a message
    public func deleteMessage(messageId: String) async {
        do {
            try await client.deleteMessage(messageId)
        } catch {
            self.error = error
        }
    }

    /// Edit a message
    public func editMessage(messageId: String, newContent: String) async {
        do {
            let _ = try await client.editMessage(messageId, content: newContent)
        } catch {
            self.error = error
        }
    }

    /// Add a reaction to a message
    public func addReaction(messageId: String, emoji: String) async {
        do {
            let _ = try await client.addReaction(messageId, emoji: emoji)
        } catch {
            self.error = error
        }
    }

    /// Remove a reaction from a message
    public func removeReaction(messageId: String, emoji: String) async {
        do {
            try await client.removeReaction(messageId, emoji: emoji)
        } catch {
            self.error = error
        }
    }

    /// Publish typing indicator (throttled)
    public func publishTyping() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingTime) >= 2 else { return }

        lastTypingTime = now
        client.publishTyping(roomId)
    }

    /// Mark messages as read
    public func markAsRead() async {
        do {
            try await client.markAsRead(roomId)
        } catch {
            // Ignore read errors
        }
    }

    /// Clear error state
    public func clearError() {
        error = nil
    }

    /// Clean up resources
    public func dispose() {
        cancellables.removeAll()
        typingTimers.values.forEach { $0.invalidate() }
        typingTimers.removeAll()
        client.unsubscribeRoom(roomId)
    }

    // MARK: - Private Methods

    private func startEventCollection() {
        // New messages
        client.onMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard message.roomId == self.roomId else { return }

                // Check if this is a confirmation for a pending message
                if let pendingIndex = self.messages.firstIndex(where: {
                    $0.isPending && $0.content == message.content &&
                    $0.senderUserId == message.senderUserId
                }) {
                    self.messages[pendingIndex] = message
                } else if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.insert(message, at: 0)
                }
            }
            .store(in: &cancellables)

        // Message deletions
        client.onMessageDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                if let index = self.messages.firstIndex(where: { $0.id == event.messageId }) {
                    let msg = self.messages[index]
                    self.messages[index] = Message(
                        id: msg.id,
                        roomId: msg.roomId,
                        senderUserId: msg.senderUserId,
                        content: msg.content,
                        type: msg.type,
                        attachments: msg.attachments,
                        metadata: msg.metadata,
                        replyToId: msg.replyToId,
                        replyTo: msg.replyTo,
                        isDeleted: true,
                        createdAt: msg.createdAt,
                        isEdited: msg.isEdited,
                        editedAt: msg.editedAt,
                        editHistory: msg.editHistory,
                        isPinned: msg.isPinned,
                        pinnedAt: msg.pinnedAt,
                        pinnedBy: msg.pinnedBy,
                        reactions: msg.reactions,
                        isPending: msg.isPending,
                        isFailed: msg.isFailed
                    )
                }
            }
            .store(in: &cancellables)

        // Message edits
        client.onMessageEdited
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                if let index = self.messages.firstIndex(where: { $0.id == event.messageId }) {
                    let msg = self.messages[index]
                    self.messages[index] = Message(
                        id: msg.id,
                        roomId: msg.roomId,
                        senderUserId: msg.senderUserId,
                        content: event.content,
                        type: msg.type,
                        attachments: msg.attachments,
                        metadata: msg.metadata,
                        replyToId: msg.replyToId,
                        replyTo: msg.replyTo,
                        isDeleted: msg.isDeleted,
                        createdAt: msg.createdAt,
                        isEdited: true,
                        editedAt: event.editedAt,
                        editHistory: msg.editHistory,
                        isPinned: msg.isPinned,
                        pinnedAt: msg.pinnedAt,
                        pinnedBy: msg.pinnedBy,
                        reactions: msg.reactions,
                        isPending: msg.isPending,
                        isFailed: msg.isFailed
                    )
                }
            }
            .store(in: &cancellables)

        // Reactions
        client.onReactionEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                if let index = self.messages.firstIndex(where: { $0.id == event.messageId }) {
                    let msg = self.messages[index]
                    var reactions = msg.reactions ?? []

                    if event.added {
                        if !reactions.contains(where: { $0.userId == event.userId && $0.emoji == event.emoji }) {
                            reactions.append(Reaction(
                                id: "\(event.userId)_\(event.emoji)",
                                messageId: event.messageId,
                                userId: event.userId,
                                emoji: event.emoji,
                                createdAt: Date()
                            ))
                        }
                    } else {
                        reactions.removeAll { $0.userId == event.userId && $0.emoji == event.emoji }
                    }

                    self.messages[index] = Message(
                        id: msg.id,
                        roomId: msg.roomId,
                        senderUserId: msg.senderUserId,
                        content: msg.content,
                        type: msg.type,
                        attachments: msg.attachments,
                        metadata: msg.metadata,
                        replyToId: msg.replyToId,
                        replyTo: msg.replyTo,
                        isDeleted: msg.isDeleted,
                        createdAt: msg.createdAt,
                        isEdited: msg.isEdited,
                        editedAt: msg.editedAt,
                        editHistory: msg.editHistory,
                        isPinned: msg.isPinned,
                        pinnedAt: msg.pinnedAt,
                        pinnedBy: msg.pinnedBy,
                        reactions: reactions,
                        isPending: msg.isPending,
                        isFailed: msg.isFailed
                    )
                }
            }
            .store(in: &cancellables)

        // Typing indicators
        client.onTypingEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                guard event.roomId == self.roomId else { return }
                guard event.userId != self.currentUserId else { return }

                if !self.typingUsers.contains(event.userId) {
                    self.typingUsers.append(event.userId)
                }

                // Cancel existing timer and start new one
                self.typingTimers[event.userId]?.invalidate()
                self.typingTimers[event.userId] = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.typingUsers.removeAll { $0 == event.userId }
                    }
                }
            }
            .store(in: &cancellables)

        // Presence changes
        client.onPresenceChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                guard event.roomId == self.roomId else { return }

                if event.isOnline {
                    self.onlineUsers.insert(event.userId)
                } else {
                    self.onlineUsers.remove(event.userId)
                }
            }
            .store(in: &cancellables)

        // Read receipts
        client.onReadReceipt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                guard event.roomId == self.roomId else { return }
                guard event.userId != self.currentUserId else { return }

                let date = event.readAt
                if self.otherUserLastRead == nil || date > self.otherUserLastRead! {
                    self.otherUserLastRead = date
                }
            }
            .store(in: &cancellables)
    }
}

/// View modifier that provides ChatChannelState
public struct ChatChannelScope<Content: View>: View {
    @Environment(\.riviumChatClient) private var client
    @StateObject private var state: ChatChannelState
    private let roomId: String
    private let currentUserId: String
    private let content: (ChatChannelState) -> Content

    public init(
        roomId: String,
        currentUserId: String,
        @ViewBuilder content: @escaping (ChatChannelState) -> Content
    ) {
        self.roomId = roomId
        self.currentUserId = currentUserId
        self.content = content

        // Note: This creates a placeholder state that will be replaced
        // The actual state is created in onAppear when we have the client
        _state = StateObject(wrappedValue: ChatChannelState(
            client: RiviumChatClient(config: RiviumChatConfig(apiKey: "", userId: "")),
            roomId: roomId,
            currentUserId: currentUserId
        ))
    }

    public var body: some View {
        content(state)
            .task {
                if let _ = client {
                    await state.initialize()
                }
            }
            .onDisappear {
                state.dispose()
            }
    }
}
