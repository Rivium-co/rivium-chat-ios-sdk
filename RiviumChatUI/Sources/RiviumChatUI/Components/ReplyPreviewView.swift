import SwiftUI
import RiviumChat

/// A view that displays a reply preview (quoted message).
/// Used both in message bubbles and in the input area when replying.
public struct ReplyPreviewView: View {
    let message: Message
    var senderName: String?
    var inBubble: Bool = true
    var isMe: Bool = false
    var onTap: (() -> Void)?
    var onClose: (() -> Void)?
    var accentColor: Color?
    var maxLines: Int = 2

    @Environment(\.riviumChatColors) private var colors

    public init(
        message: Message,
        senderName: String? = nil,
        inBubble: Bool = true,
        isMe: Bool = false,
        onTap: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        accentColor: Color? = nil,
        maxLines: Int = 2
    ) {
        self.message = message
        self.senderName = senderName
        self.inBubble = inBubble
        self.isMe = isMe
        self.onTap = onTap
        self.onClose = onClose
        self.accentColor = accentColor
        self.maxLines = maxLines
    }

    private var borderColor: Color {
        accentColor ?? (isMe && inBubble ? Color.white.opacity(0.5) : colors.linkText)
    }

    private var backgroundColor: Color {
        if inBubble {
            return isMe ? Color.white.opacity(0.1) : colors.replyBackground
        } else {
            return colors.replyBackground
        }
    }

    private var textColor: Color {
        if isMe && inBubble {
            return Color.white.opacity(0.8)
        } else {
            return Color.secondary
        }
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Left accent border
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 3)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    // Sender name
                    if let senderName = senderName {
                        Text(senderName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(borderColor)
                            .lineLimit(1)
                    }

                    // Message content preview
                    replyContentPreview
                }

                Spacer(minLength: 0)

                // Attachment thumbnail
                if hasMediaAttachment {
                    attachmentThumbnail
                }

                // Close button (for input area)
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                }
            }
            .padding(8)
            .frame(height: 48)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private var replyContentPreview: some View {
        if message.isDeleted {
            HStack(spacing: 4) {
                Image(systemName: "nosign")
                    .font(.caption2)
                Text("Message deleted")
                    .font(.caption)
                    .italic()
            }
            .foregroundColor(textColor)
        } else {
            HStack(spacing: 4) {
                if let icon = contentIcon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundColor(textColor)
                }
                Text(contentText)
                    .font(.caption)
                    .foregroundColor(textColor)
                    .lineLimit(maxLines)
            }
        }
    }

    private var contentText: String {
        switch message.type {
        case .image:
            return "Photo"
        case .file:
            return message.attachments?.first?.name ?? "File"
        case .system:
            return message.content
        default:
            return message.content
        }
    }

    private var contentIcon: String? {
        switch message.type {
        case .image:
            return "photo"
        case .file:
            return "paperclip"
        default:
            return nil
        }
    }

    private var hasMediaAttachment: Bool {
        message.type == .image && !(message.attachments?.isEmpty ?? true)
    }

    @ViewBuilder
    private var attachmentThumbnail: some View {
        if let _ = message.attachments?.first {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                )
        }
    }
}

/// A compact reply indicator shown in the input area.
public struct ReplyInputPreview: View {
    let message: Message
    var senderName: String?
    let onClose: () -> Void
    var onTap: (() -> Void)?

    @Environment(\.riviumChatColors) private var colors

    public init(
        message: Message,
        senderName: String? = nil,
        onClose: @escaping () -> Void,
        onTap: (() -> Void)? = nil
    ) {
        self.message = message
        self.senderName = senderName
        self.onClose = onClose
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Left border
            Rectangle()
                .fill(colors.linkText)
                .frame(width: 4)

            // Reply icon
            Image(systemName: "arrowshape.turn.up.left.fill")
                .foregroundColor(colors.linkText)
                .font(.subheadline)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(senderName ?? "message")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.linkText)

                Text(previewText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 56)
        .background(colors.replyBackground)
        .onTapGesture {
            onTap?()
        }
    }

    private var previewText: String {
        if message.isDeleted {
            return "Message deleted"
        }
        switch message.type {
        case .image:
            return "Photo"
        case .file:
            return message.attachments?.first?.name ?? "File"
        default:
            return message.content
        }
    }
}
