import SwiftUI
import Combine
// PhotosUI would be imported by the customer's app for file upload
import RiviumChat
import RiviumChatUI

/// Chat screen for an order.
public struct OrderChatScreen: View {
    let order: Order
    let currentUser: DemoUser
    let client: RiviumChatClient
    let onBack: () -> Void

    @State private var room: Room?
    @State private var messages: [Message] = []
    @State private var pinnedMessages: [Message] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var messageText = ""
    @State private var replyingTo: Message?
    @State private var otherUserTyping = false
    @State private var otherUserOnline = false
    @State private var showSearch = false
    @State private var showPinnedMessages = false
    @State private var selectedMessage: Message?
    @State private var showReactionPicker = false
    @State private var typingResetTask: Task<Void, Never>?
    @State private var otherUserLastRead: Date?
    @State private var hasMoreMessages = false
    @State private var isLoadingMore = false
    @State private var showAttachmentAlert = false

    private var otherUser: DemoUser {
        DemoUsers.getOtherUser(currentUserId: currentUser.id)
    }

    public init(
        order: Order,
        currentUser: DemoUser,
        client: RiviumChatClient,
        onBack: @escaping () -> Void
    ) {
        self.order = order
        self.currentUser = currentUser
        self.client = client
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Order header
            OrderHeaderWidget(order: order)

            // Pinned messages banner
            if showPinnedMessages && !pinnedMessages.isEmpty {
                pinnedMessagesBanner
            }

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                errorView(error)
            } else {
                chatContent
            }
        }
        .navigationTitle(otherUser.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: URL(string: otherUser.avatarUrl ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.accentColor.opacity(0.2))
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())

                        Circle()
                            .fill(otherUserOnline ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(otherUser.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(otherUserTyping ? "typing..." : (otherUserOnline ? "Online" : "Offline"))
                            .font(.caption2)
                            .foregroundColor(otherUserTyping ? .accentColor : .secondary)
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showSearch = true }) {
                    Image(systemName: "magnifyingglass")
                }

                if !pinnedMessages.isEmpty {
                    Button(action: { showPinnedMessages.toggle() }) {
                        Image(systemName: "pin.fill")
                            .foregroundColor(showPinnedMessages ? .accentColor : .primary)
                    }
                }
            }
        }
        .task {
            await loadChat()
        }
        .onDisappear {
            typingResetTask?.cancel()
            if let room = room {
                // Leave presence/typing but keep chat channel for unread badge updates
                client.leaveRoom(room.id)
                // Mark as read when leaving the chat screen
                Task { try? await client.markAsRead(room.id) }
            }
        }
        .onReceive(client.onMessage) { message in
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
                // Mark as read when we receive a new message while chat is open
                if message.senderUserId != currentUser.id, let room = room {
                    Task {
                        print("[RiviumChat] Marking room as read: \(room.id)")
                        do {
                            try await client.markAsRead(room.id)
                            print("[RiviumChat] markAsRead succeeded")
                        } catch {
                            print("[RiviumChat] markAsRead failed: \(error)")
                        }
                    }
                }
            }
        }
        .onReceive(client.onTypingEvent) { event in
            print("[RiviumChat] Typing event: userId=\(event.userId), isTyping=\(event.isTyping)")
            if event.userId != currentUser.id {
                if event.isTyping {
                    if !otherUserTyping {
                        otherUserTyping = true
                    }
                    typingResetTask?.cancel()
                    typingResetTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run { otherUserTyping = false }
                    }
                }
            }
        }
        .onReceive(client.onPresenceChange) { event in
            if event.userId == otherUser.id {
                otherUserOnline = event.isOnline
            }
        }
        .onReceive(client.onReadReceipt) { event in
            print("[RiviumChat] Read receipt: userId=\(event.userId), readAt=\(event.readAt)")
            if event.userId == otherUser.id {
                if otherUserLastRead == nil || event.readAt > otherUserLastRead! {
                    otherUserLastRead = event.readAt
                }
            }
        }
        .onReceive(client.onReactionEvent) { event in
            if let index = messages.firstIndex(where: { $0.id == event.messageId }) {
                var msg = messages[index]
                var reactions = msg.reactions ?? []
                if event.added {
                    let reaction = Reaction(
                        id: event.reactionId ?? UUID().uuidString,
                        messageId: event.messageId,
                        userId: event.userId,
                        emoji: event.emoji,
                        createdAt: Date()
                    )
                    reactions.append(reaction)
                } else {
                    reactions.removeAll { $0.userId == event.userId && $0.emoji == event.emoji }
                }
                // Recreate message with updated reactions
                messages[index] = Message(
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
        .onReceive(client.onMessagePinChanged) { event in
            if event.pinned {
                if let msg = messages.first(where: { $0.id == event.messageId }) {
                    pinnedMessages.append(msg)
                }
            } else {
                pinnedMessages.removeAll { $0.id == event.messageId }
            }
        }
        .onReceive(client.onMessageDeleted) { event in
            messages.removeAll { $0.id == event.messageId }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                MessageSearchOverlay(
                    messages: messages,
                    onMessageSelected: { _ in showSearch = false },
                    onClose: { showSearch = false }
                )
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // Spacer to push messages to bottom when there are few messages
                        Spacer()
                            .frame(minHeight: 0)
                            .id("top-spacer")

                        // Load more trigger
                        if hasMoreMessages {
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await loadMoreMessages() }
                                    }
                            }
                        }

                        ForEach(messages, id: \.id) { message in
                            let isMe = message.senderUserId == currentUser.id
                            let isPinned = pinnedMessages.contains { $0.id == message.id }

                            ChatMessageBubble(
                                message: message,
                                isMe: isMe,
                                isRead: isMe && otherUserLastRead != nil && message.createdAt <= otherUserLastRead!,
                                showAvatar: !isMe,
                                otherUserName: otherUser.name,
                                onReactionTap: { emoji in
                                    Task {
                                        try? await client.addReaction(message.id, emoji: emoji)
                                    }
                                },
                                onLongPress: {
                                    selectedMessage = message
                                }
                            )
                            .swipeToReply {
                                replyingTo = message
                            }
                            .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .dismissKeyboardOnScroll()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .onAppear {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }

            // Reply preview
            if let replyMessage = replyingTo {
                ReplyInputPreview(
                    message: replyMessage,
                    senderName: replyMessage.senderUserId == currentUser.id ? currentUser.name : otherUser.name,
                    onClose: { replyingTo = nil }
                )
            }

            // Input field
            ChatInputField(
                text: $messageText,
                onSend: { text in
                    Task {
                        await sendMessage(text)
                    }
                },
                onTyping: {
                    if let room = room {
                        client.publishTyping(room.id)
                    }
                },
                onAttachmentTap: {
                    showAttachmentAlert = true
                },
                placeholder: "Message \(otherUser.name)..."
            )
        }
        .confirmationDialog("Message Actions", isPresented: .init(
            get: { selectedMessage != nil },
            set: { if !$0 { selectedMessage = nil } }
        )) {
            if let message = selectedMessage {
                Button("Reply") {
                    replyingTo = message
                    selectedMessage = nil
                }

                Button("React") {
                    showReactionPicker = true
                }

                let isPinned = pinnedMessages.contains { $0.id == message.id }
                Button(isPinned ? "Unpin" : "Pin") {
                    Task {
                        if isPinned {
                            try? await client.unpinMessage(message.id)
                        } else {
                            _ = try? await client.pinMessage(message.id)
                        }
                    }
                    selectedMessage = nil
                }

                if message.senderUserId == currentUser.id {
                    Button("Delete", role: .destructive) {
                        Task {
                            try? await client.deleteMessage(message.id)
                        }
                        selectedMessage = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    selectedMessage = nil
                }
            }
        }
        .sheet(isPresented: $showReactionPicker) {
            MessageReactionPicker(
                onReactionSelected: { emoji in
                    Task {
                        if let message = selectedMessage {
                            try? await client.addReaction(message.id, emoji: emoji)
                        }
                    }
                    showReactionPicker = false
                    selectedMessage = nil
                }
            )
            .presentationDetents([.height(200)])
        }
        .alert("File Upload", isPresented: $showAttachmentAlert) {
            Button("OK") {}
        } message: {
            Text("To enable file uploads, provide a fileUploader in RiviumChatConfig that uploads to your own server and returns the file URL.")
        }
    }

    private var pinnedMessagesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(pinnedMessages.count) pinned message\(pinnedMessages.count > 1 ? "s" : "")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)

                if let first = pinnedMessages.first {
                    Text(first.content)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { showPinnedMessages = false }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text(error)
                .foregroundColor(.secondary)

            Button("Retry") {
                Task { await loadChat() }
            }
        }
    }

    private func loadChat() async {
        // Prevent duplicate loads
        guard room == nil else { return }
        isLoading = true
        error = nil

        do {
            // Ensure connection is established before proceeding
            if !client.isConnected {
                print("[RiviumChat] Waiting for connection...")
                try await client.connect()
                print("[RiviumChat] Connected!")
            }

            print("[RiviumChat] Loading chat for order: \(order.id)")

            // Use findOrCreateRoom — same as Flutter example
            let loadedRoom = try await client.findOrCreateRoom(
                externalId: order.id,
                participants: [
                    [
                        "externalUserId": order.buyerId,
                        "displayName": DemoUsers.buyer.name,
                        "role": "member"
                    ],
                    [
                        "externalUserId": order.sellerId,
                        "displayName": DemoUsers.seller.name,
                        "role": "member"
                    ]
                ],
                metadata: [
                    "orderId": order.id,
                    "orderNumber": order.orderNumber,
                    "type": "order_support"
                ]
            )
            print("[RiviumChat] Room loaded: \(loadedRoom.id)")

            room = loadedRoom
            client.subscribeRoom(loadedRoom.id)

            // Load initial read state from the other user's participant data
            let otherParticipant = loadedRoom.participants.first(where: { $0.externalUserId == otherUser.id })
            otherUserLastRead = otherParticipant?.lastReadAt
            print("[RiviumChat] Other user \(otherUser.id) lastReadAt: \(String(describing: otherUserLastRead)), participants: \(loadedRoom.participants.map { "\($0.externalUserId): \(String(describing: $0.lastReadAt))" })")

            // Load messages
            let paginatedMessages = try await client.getMessages(loadedRoom.id, limit: 30)
            messages = paginatedMessages.messages.sorted { $0.createdAt < $1.createdAt }
            hasMoreMessages = paginatedMessages.hasMore
            print("[RiviumChat] Loaded \(messages.count) messages, hasMore: \(hasMoreMessages)")

            // Load pinned messages
            let pinned = try await client.getPinnedMessages(loadedRoom.id)
            pinnedMessages = pinned

            // Wait briefly for presence subscription to be established before querying
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            // Mark messages as read
            try? await client.markAsRead(loadedRoom.id)

            // Query initial presence after subscription is established
            let onlineUsers = try await client.getRoomPresence(loadedRoom.id)
            otherUserOnline = onlineUsers.contains(otherUser.id)
            print("[RiviumChat] Presence: \(onlineUsers), otherUser \(otherUser.id) online: \(otherUserOnline)")

            isLoading = false
        } catch {
            print("[RiviumChat] loadChat error: \(error)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func sendMessage(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let room = room else { return }

        let replyToId = replyingTo?.id
        replyingTo = nil

        do {
            let sentMessage = try await client.sendMessage(
                room.id,
                content: content,
                replyToId: replyToId
            )
            // Add to list immediately from API response
            if !messages.contains(where: { $0.id == sentMessage.id }) {
                messages.append(sentMessage)
            }
        } catch {
            print("Failed to send message: \(error)")
        }
    }

    private func loadMoreMessages() async {
        guard let room = room, hasMoreMessages, !isLoadingMore else { return }
        guard let oldestMessage = messages.first else { return }

        isLoadingMore = true
        do {
            let paginatedMessages = try await client.getMessages(room.id, limit: 30, before: oldestMessage.id)
            let olderMessages = paginatedMessages.messages.sorted { $0.createdAt < $1.createdAt }
            messages.insert(contentsOf: olderMessages, at: 0)
            hasMoreMessages = paginatedMessages.hasMore
            print("[RiviumChat] Loaded \(olderMessages.count) more messages, hasMore: \(hasMoreMessages)")
        } catch {
            print("[RiviumChat] Failed to load more messages: \(error)")
        }
        isLoadingMore = false
    }
}

private extension View {
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
