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

    @Environment(\.riviumChatClient) private var client
    @StateObject private var holder = ChatChannelStateHolder()

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
    }

    public var body: some View {
        if let client {
            ChatScreenContent(
                state: holder.state(client: client, roomId: roomId, currentUserId: currentUserId),
                currentUserId: currentUserId,
                isReadOnly: isReadOnly,
                messageBuilder: messageBuilder,
                onImageTap: onImageTap,
                userDisplayNames: userDisplayNames
            )
        } else {
            // No client in the environment yet (wrap in RiviumChatScope or
            // RiviumChatProvider).
            ProgressView()
        }
    }
}

/// The chat screen for a state that has a real client.
private struct ChatScreenContent: View {
    @ObservedObject var state: ChatChannelState
    let currentUserId: String
    let isReadOnly: Bool
    let messageBuilder: ((Message, Bool, Bool) -> AnyView)?
    let onImageTap: ((String) -> Void)?
    let userDisplayNames: [String: String]

    @State private var messageText = ""
    @State private var selectedMessage: Message?
    @State private var showContextMenu = false
    @State private var showReactionPicker = false
    @State private var showAttachmentPicker = false
    @State private var editingMessage: Message?
    @State private var editText = ""
    @State private var showEditSheet = false
    /// Set by the options sheet; the edit sheet opens once that one is gone.
    @State private var editAfterOptions: Message?

    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions

    /// Names from the room's participants; names the app passes win.
    private var displayNames: [String: String] {
        state.participantDisplayNames.merging(userDisplayNames) { _, app in app }
    }

    /// "You" for the current user, else the display name (user id fallback).
    private func name(for userId: String) -> String {
        userId == currentUserId ? "You" : (displayNames[userId] ?? userId)
    }

    init(
        state: ChatChannelState,
        currentUserId: String,
        isReadOnly: Bool,
        messageBuilder: ((Message, Bool, Bool) -> AnyView)?,
        onImageTap: ((String) -> Void)?,
        userDisplayNames: [String: String]
    ) {
        self.state = state
        self.currentUserId = currentUserId
        self.isReadOnly = isReadOnly
        self.messageBuilder = messageBuilder
        self.onImageTap = onImageTap
        self.userDisplayNames = userDisplayNames
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ZStack {
                if state.isInitialLoading {
                    ProgressView()
                } else if let error = state.error, state.messages.isEmpty {
                    // A failed action with messages on screen (a pin or a
                    // reaction) keeps the conversation visible.
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
                    isEnabled: !state.isInitialLoading,
                    replyingToName: state.replyingTo.map { name(for: $0.senderUserId) }
                )
            }
        }
        .task {
            await state.initialize()
        }
        .onDisappear {
            state.dispose()
        }
        .sheet(isPresented: $showContextMenu, onDismiss: {
            if let message = editAfterOptions {
                editAfterOptions = nil
                startEditing(message)
            }
        }) {
            if let message = selectedMessage {
                contextMenuSheet(for: message)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
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
                            userDisplayNames: displayNames
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
                otherUserName: displayNames[message.senderUserId],
                mentionDisplayNames: displayNames,
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
                onImageTap: onImageTap,
                replySenderName: message.replyTo.map { name(for: $0.senderUserId) }
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
                        editAfterOptions = message
                        showContextMenu = false
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                Button {
                    togglePin(message)
                    showContextMenu = false
                } label: {
                    if message.isPinned {
                        Label("Unpin", systemImage: "pin.slash")
                    } else {
                        Label("Pin", systemImage: "pin")
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

    private var editSheet: some View {
        NavigationView {
            TextEditor(text: $editText)
                .padding()
                .navigationTitle("Edit message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showEditSheet = false
                            editingMessage = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEdit()
                        }
                    }
                }
        }
        .presentationDetentsIfAvailable(.medium)
    }

    // MARK: - Helper Methods

    private func startEditing(_ message: Message) {
        editingMessage = message
        editText = message.content
        showEditSheet = true
    }

    private func saveEdit() {
        let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = editingMessage, !newContent.isEmpty, newContent != message.content {
            Task {
                await state.editMessage(messageId: message.id, newContent: newContent)
            }
        }
        showEditSheet = false
        editingMessage = nil
    }

    private func togglePin(_ message: Message) {
        Task {
            if message.isPinned {
                await state.unpinMessage(messageId: message.id)
            } else {
                await state.pinMessage(messageId: message.id)
            }
        }
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
            startEditing(message)
        case .delete:
            Task {
                await state.deleteMessage(messageId: message.id)
            }
        case .pin:
            togglePin(message)
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
