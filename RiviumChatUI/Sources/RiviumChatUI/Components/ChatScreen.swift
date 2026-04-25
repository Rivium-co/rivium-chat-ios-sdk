import SwiftUI
import RiviumChat

/// File uploader protocol for handling attachment uploads
public protocol FileUploader {
    func uploadFile(url: URL, mimeType: String?, fileName: String?) async throws -> Attachment?
}

/// Complete chat screen with messages, input, and typing indicator
public struct ChatScreen: View {
    let roomId: String
    let currentUserId: String
    var isReadOnly: Bool = false
    var messageBuilder: ((Message, Bool, Bool) -> AnyView)? = nil
    var fileUploader: FileUploader? = nil
    var onImageTap: ((String) -> Void)? = nil
    var userDisplayNames: [String: String] = [:]

    @StateObject private var state: ChatChannelState
    @State private var messageText = ""
    @State private var selectedMessage: Message?
    @State private var showContextMenu = false
    @State private var showReactionPicker = false
    @State private var showAttachmentPicker = false

    @Environment(\.riviumChatClient) private var client
    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions

    public init(
        roomId: String,
        currentUserId: String,
        isReadOnly: Bool = false,
        messageBuilder: ((Message, Bool, Bool) -> AnyView)? = nil,
        fileUploader: FileUploader? = nil,
        onImageTap: ((String) -> Void)? = nil,
        userDisplayNames: [String: String] = [:]
    ) {
        self.roomId = roomId
        self.currentUserId = currentUserId
        self.isReadOnly = isReadOnly
        self.messageBuilder = messageBuilder
        self.fileUploader = fileUploader
        self.onImageTap = onImageTap
        self.userDisplayNames = userDisplayNames

        // Create placeholder state - actual client will be injected via environment
        _state = StateObject(wrappedValue: ChatChannelState(
            client: RiviumChatClient(config: RiviumChatConfig(apiKey: "", userId: "")),
            roomId: roomId,
            currentUserId: currentUserId
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ZStack {
                if state.isInitialLoading {
                    ProgressView()
                } else if let error = state.error {
                    errorView(error)
                } else if state.messages.isEmpty {
                    emptyView
                } else {
                    messagesList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input field
            if !isReadOnly {
                ChatInputField(
                    text: $messageText,
                    onSend: { content in
                        Task {
                            await state.sendMessage(content: content)
                        }
                    },
                    onTyping: {
                        Task {
                            await state.publishTyping()
                        }
                    },
                    replyingTo: state.replyingTo,
                    onCancelReply: { state.replyingTo = nil },
                    onAttachmentTap: { showAttachmentPicker = true },
                    isEnabled: !state.isInitialLoading
                )
            }
        }
        .task {
            if let client = client {
                // Reinitialize state with actual client
                await initializeWithClient(client)
            }
        }
        .sheet(isPresented: $showContextMenu) {
            if let message = selectedMessage {
                contextMenuSheet(for: message)
            }
        }
        .sheet(isPresented: $showReactionPicker) {
            if let message = selectedMessage {
                reactionPickerSheet(for: message)
            }
        }
        .sheet(isPresented: $showAttachmentPicker) {
            attachmentPickerSheet
        }
    }

    // MARK: - Subviews

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Loading more indicator
                    if state.isLoadingMore {
                        ProgressView()
                            .padding()
                    }

                    // Messages (reversed - newest at bottom)
                    ForEach(state.messages.reversed(), id: \.id) { message in
                        messageRow(for: message)
                            .id(message.id)
                    }

                    // Typing indicator
                    if !state.typingUsers.isEmpty {
                        TypingIndicator(
                            typingUsers: state.typingUsers,
                            userDisplayNames: userDisplayNames
                        )
                    }
                }
            }
            .dismissKeyboardOnScroll()
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onAppear {
                // Scroll to bottom on appear
                if let lastMessage = state.messages.first {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: state.messages.first?.id) { _ in
                // Scroll to new messages
                if let lastMessage = state.messages.first {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(for message: Message) -> some View {
        let isMe = message.senderUserId == currentUserId
        let isRead = isMessageRead(message)

        if let builder = messageBuilder {
            builder(message, isMe, isRead)
        } else {
            ChatMessageBubble(
                message: message,
                isMe: isMe,
                isRead: isRead,
                otherUserName: userDisplayNames[message.senderUserId],
                mentionDisplayNames: userDisplayNames,
                onRetry: message.isFailed ? {
                    Task {
                        await state.retryMessage(messageId: message.id)
                    }
                } : nil,
                onReactionTap: { emoji in
                    Task {
                        await toggleReaction(messageId: message.id, emoji: emoji)
                    }
                },
                onLongPress: {
                    selectedMessage = message
                    showContextMenu = true
                },
                onImageTap: onImageTap
            )
            .messageContextMenu(
                message: message,
                isMe: isMe,
                isPinned: message.isPinned
            ) { action in
                handleContextAction(action, for: message)
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 8) {
            Text("Failed to load messages")
                .font(.headline)
                .foregroundColor(.red)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        Text("No messages yet")
            .font(.body)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func contextMenuSheet(for message: Message) -> some View {
        let isMe = message.senderUserId == currentUserId

        NavigationView {
            List {
                Button {
                    state.replyingTo = message
                    showContextMenu = false
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }

                Button {
                    UIPasteboard.general.string = message.content
                    showContextMenu = false
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if isMe {
                    Button {
                        // Would open edit dialog
                        showContextMenu = false
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                Button {
                    showContextMenu = false
                    showReactionPicker = true
                } label: {
                    Label("React", systemImage: "face.smiling")
                }

                if isMe {
                    Button(role: .destructive) {
                        Task {
                            await state.deleteMessage(messageId: message.id)
                        }
                        showContextMenu = false
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Message Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showContextMenu = false
                    }
                }
            }
        }
        .presentationDetentsIfAvailable(.medium)
    }

    @ViewBuilder
    private func reactionPickerSheet(for message: Message) -> some View {
        VStack {
            MessageReactionPicker { emoji in
                Task {
                    await state.addReaction(messageId: message.id, emoji: emoji)
                }
                showReactionPicker = false
                selectedMessage = nil
            }
            .padding()
        }
        .presentationDetentsIfAvailable(.height(100))
    }

    private var attachmentPickerSheet: some View {
        AttachmentPickerContent(
            onGalleryTap: {
                showAttachmentPicker = false
                // Would open photo picker
            },
            onCameraTap: {
                showAttachmentPicker = false
                // Would open camera
            },
            onFileTap: {
                showAttachmentPicker = false
                // Would open file picker
            }
        )
        .presentationDetentsIfAvailable(.height(150))
    }

    // MARK: - Helper Methods

    private func initializeWithClient(_ client: RiviumChatClient) async {
        // Create new state with proper client
        let newState = ChatChannelState(
            client: client,
            roomId: roomId,
            currentUserId: currentUserId
        )
        await newState.initialize()
    }

    private func isMessageRead(_ message: Message) -> Bool {
        guard message.senderUserId == currentUserId,
              let otherLastRead = state.otherUserLastRead else {
            return false
        }

        return message.createdAt <= otherLastRead
    }

    private func toggleReaction(messageId: String, emoji: String) async {
        let message = state.messages.first { $0.id == messageId }
        let hasReacted = message?.reactions?.contains { $0.userId == currentUserId && $0.emoji == emoji } ?? false

        if hasReacted {
            await state.removeReaction(messageId: messageId, emoji: emoji)
        } else {
            await state.addReaction(messageId: messageId, emoji: emoji)
        }
    }

    private func handleContextAction(_ action: MessageAction, for message: Message) {
        switch action {
        case .reply:
            state.replyingTo = message
        case .copy:
            UIPasteboard.general.string = message.content
        case .edit:
            // Would open edit dialog
            break
        case .delete:
            Task {
                await state.deleteMessage(messageId: message.id)
            }
        case .pin:
            // Would pin/unpin message
            break
        case .react:
            selectedMessage = message
            showReactionPicker = true
        }
    }
}

// MARK: - iOS 15 Compatibility

private enum DetentType {
    case medium
    case large
    case height(CGFloat)
}

private struct DetentModifier: ViewModifier {
    let detent: DetentType

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            switch detent {
            case .medium:
                content.presentationDetents([.medium])
            case .large:
                content.presentationDetents([.large])
            case .height(let h):
                content.presentationDetents([.height(h)])
            }
        } else {
            content
        }
    }
}

private extension View {
    func presentationDetentsIfAvailable(_ detent: DetentType) -> some View {
        modifier(DetentModifier(detent: detent))
    }

    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
