import SwiftUI
import RiviumChat
import SDWebImageSwiftUI

/// A message bubble component for displaying chat messages
public struct ChatMessageBubble: View {
    let message: Message
    let isMe: Bool
    var isRead: Bool = false
    var showAvatar: Bool = true
    var otherUserName: String? = nil
    var mentionDisplayNames: [String: String]? = nil
    var onRetry: (() -> Void)? = nil
    var onReactionTap: ((String) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    var onImageTap: ((String) -> Void)? = nil

    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions

    public init(
        message: Message,
        isMe: Bool,
        isRead: Bool = false,
        showAvatar: Bool = true,
        otherUserName: String? = nil,
        mentionDisplayNames: [String: String]? = nil,
        onRetry: (() -> Void)? = nil,
        onReactionTap: ((String) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onImageTap: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.isMe = isMe
        self.isRead = isRead
        self.showAvatar = showAvatar
        self.otherUserName = otherUserName
        self.mentionDisplayNames = mentionDisplayNames
        self.onRetry = onRetry
        self.onReactionTap = onReactionTap
        self.onLongPress = onLongPress
        self.onImageTap = onImageTap
    }

    public var body: some View {
        if message.isDeleted {
            deletedMessageBubble
        } else {
            regularMessageBubble
        }
    }

    private var deletedMessageBubble: some View {
        HStack {
            if isMe { Spacer() }
            Text("This message was deleted")
                .italic()
                .foregroundColor(.secondary.opacity(0.6))
                .padding(dimensions.messagePadding)
                .background(Color(UIColor.systemGray5).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: dimensions.messageBubbleRadius))
            if !isMe { Spacer() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var regularMessageBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - dimensions.maxBubbleWidthRatio))
            }

            // Avatar for other users
            if !isMe && showAvatar {
                avatarView
            } else if !isMe {
                Spacer().frame(width: dimensions.smallAvatarSize + 8)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // Reply preview
                if let replyTo = message.replyTo {
                    ReplyPreview(message: replyTo, isMe: isMe)
                }

                // Message bubble
                bubbleContent
                    .background(bubbleColor)
                    .clipShape(bubbleShape)
                    .onLongPressGesture {
                        onLongPress?()
                    }

                // Reactions
                if !(message.reactions?.isEmpty ?? true) {
                    reactionsView
                }
            }

            if !isMe {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - dimensions.maxBubbleWidthRatio))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var avatarView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: dimensions.smallAvatarSize, height: dimensions.smallAvatarSize)
            .overlay(
                Text(String((otherUserName ?? "U").prefix(1)).uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            )
    }

    private var bubbleColor: Color {
        if message.isFailed {
            return colors.failedMessage.opacity(0.2)
        } else if message.isPending {
            return isMe ? colors.myMessageBubble.opacity(0.6) : colors.otherMessageBubble
        } else {
            return isMe ? colors.myMessageBubble : colors.otherMessageBubble
        }
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(
            cornerRadius: dimensions.messageBubbleRadius,
            style: .continuous
        )
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Image attachments
            let imageAttachments = (message.attachments ?? []).filter { $0.mimeType?.hasPrefix("image/") == true }
            ForEach(imageAttachments, id: \.url) { attachment in
                WebImage(url: URL(string: attachment.url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(ProgressView())
                }
                .frame(maxWidth: dimensions.imagePreviewSize, maxHeight: dimensions.imagePreviewSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    onImageTap?(attachment.url)
                }
            }

            // File attachments
            let fileAttachments = (message.attachments ?? []).filter { $0.mimeType?.hasPrefix("image/") != true }
            ForEach(fileAttachments, id: \.url) { attachment in
                FileAttachmentChip(
                    name: attachment.name ?? "File",
                    size: attachment.size.map { Int64($0) },
                    isMe: isMe
                )
            }

            // Message content
            if !message.content.isEmpty {
                Text(message.content)
                    .foregroundColor(isMe ? colors.myMessageText : colors.otherMessageText)
            }

            // Timestamp and status row
            HStack(spacing: 4) {
                if message.isEdited {
                    Text("edited")
                        .font(.caption2)
                        .italic()
                        .foregroundColor(colors.timestampText)
                }

                Text(formatTimestamp(message.createdAt))
                    .font(.caption2)
                    .foregroundColor(isMe ? colors.myMessageText.opacity(0.7) : colors.timestampText)

                if isMe {
                    statusIndicator
                }
            }
        }
        .padding(dimensions.messagePadding)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if message.isFailed {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(colors.failedMessage)
                    .font(.caption)
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(colors.failedMessage)
                            .font(.caption)
                    }
                }
            }
        } else if message.isPending {
            Image(systemName: "clock")
                .foregroundColor(colors.myMessageText.opacity(0.7))
                .font(.caption)
        } else if isRead {
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .foregroundColor(colors.myMessageText.opacity(0.9))
            .font(.system(size: 9, weight: .bold))
        } else {
            Image(systemName: "checkmark")
                .foregroundColor(colors.myMessageText.opacity(0.7))
                .font(.caption)
        }
    }

    private var reactionsView: some View {
        let groupedReactions = Dictionary(grouping: message.reactions ?? [], by: { $0.emoji })

        return HStack(spacing: 4) {
            ForEach(Array(groupedReactions.keys), id: \.self) { emoji in
                ReactionPill(
                    emoji: emoji,
                    count: groupedReactions[emoji]?.count ?? 0,
                    onTap: { onReactionTap?(emoji) }
                )
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct ReplyPreview: View {
    let message: Message
    let isMe: Bool

    @Environment(\.riviumChatColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(isMe ? colors.myMessageBubble : Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderUserId)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isMe ? colors.myMessageBubble : Color.accentColor)

                Text(message.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(colors.replyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ReactionPill: View {
    let emoji: String
    let count: Int
    let onTap: () -> Void

    @Environment(\.riviumChatDimensions) private var dimensions

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.caption)
                if count > 1 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.systemGray5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FileAttachmentChip: View {
    let name: String
    let size: Int64?
    let isMe: Bool

    @Environment(\.riviumChatColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Text("📎")

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(isMe ? colors.myMessageText : .primary)

                if let size = size {
                    Text(formatFileSize(size))
                        .font(.caption2)
                        .foregroundColor(isMe ? colors.myMessageText.opacity(0.7) : colors.timestampText)
                }
            }
        }
        .padding(8)
        .background(isMe ? colors.myMessageText.opacity(0.1) : Color(UIColor.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        switch bytes {
        case ..<1024:
            return "\(bytes) B"
        case ..<(1024 * 1024):
            return "\(bytes / 1024) KB"
        default:
            return "\(bytes / (1024 * 1024)) MB"
        }
    }
}
