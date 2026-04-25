import SwiftUI
import RiviumChat

/// Input field for composing chat messages
public struct ChatInputField: View {
    @Binding var text: String
    let onSend: (String) -> Void
    var onTyping: (() -> Void)? = nil
    var replyingTo: Message? = nil
    var onCancelReply: (() -> Void)? = nil
    var onAttachmentTap: (() -> Void)? = nil
    var onCameraTap: (() -> Void)? = nil
    var onEmojiTap: (() -> Void)? = nil
    var onVoiceRecordStart: (() -> Void)? = nil
    var isEnabled: Bool = true
    var placeholder: String = "Type a message..."

    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        onSend: @escaping (String) -> Void,
        onTyping: (() -> Void)? = nil,
        replyingTo: Message? = nil,
        onCancelReply: (() -> Void)? = nil,
        onAttachmentTap: (() -> Void)? = nil,
        onCameraTap: (() -> Void)? = nil,
        onEmojiTap: (() -> Void)? = nil,
        onVoiceRecordStart: (() -> Void)? = nil,
        isEnabled: Bool = true,
        placeholder: String = "Type a message..."
    ) {
        self._text = text
        self.onSend = onSend
        self.onTyping = onTyping
        self.replyingTo = replyingTo
        self.onCancelReply = onCancelReply
        self.onAttachmentTap = onAttachmentTap
        self.onCameraTap = onCameraTap
        self.onEmojiTap = onEmojiTap
        self.onVoiceRecordStart = onVoiceRecordStart
        self.isEnabled = isEnabled
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Reply preview
            if let replyingTo = replyingTo {
                ReplyInputPreview(
                    message: replyingTo,
                    onClose: { onCancelReply?() }
                )
            }

            // Input bar
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment button
                if let onAttachmentTap = onAttachmentTap {
                    Button(action: onAttachmentTap) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .disabled(!isEnabled)
                    .frame(width: 40, height: 40)
                }

                // Text field container
                HStack(alignment: .bottom, spacing: 8) {
                    // Emoji button
                    if let onEmojiTap = onEmojiTap {
                        Button(action: onEmojiTap) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                        .disabled(!isEnabled)
                    }

                    // Text field
                    if #available(iOS 16.0, *) {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($isFocused)
                            .disabled(!isEnabled)
                            .onChange(of: text) { _ in
                                if !text.isEmpty {
                                    onTyping?()
                                }
                            }
                    } else {
                        TextField(placeholder, text: $text)
                            .focused($isFocused)
                            .disabled(!isEnabled)
                            .onChange(of: text) { _ in
                                if !text.isEmpty {
                                    onTyping?()
                                }
                            }
                    }

                    // Camera button (when text is empty)
                    if text.isEmpty, let onCameraTap = onCameraTap {
                        Button(action: onCameraTap) {
                            Image(systemName: "camera")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                        .disabled(!isEnabled)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: dimensions.inputFieldRadius))

                // Send / Voice button
                Button(action: {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let messageText = text
                        text = ""
                        onSend(messageText)
                    } else {
                        onVoiceRecordStart?()
                    }
                }) {
                    Image(systemName: text.isEmpty ? "mic.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .disabled(!isEnabled)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
        }
    }
}

/// Attachment picker sheet content
public struct AttachmentPickerContent: View {
    let onGalleryTap: () -> Void
    let onCameraTap: () -> Void
    let onFileTap: () -> Void

    public init(
        onGalleryTap: @escaping () -> Void,
        onCameraTap: @escaping () -> Void,
        onFileTap: @escaping () -> Void
    ) {
        self.onGalleryTap = onGalleryTap
        self.onCameraTap = onCameraTap
        self.onFileTap = onFileTap
    }

    public var body: some View {
        HStack(spacing: 40) {
            AttachmentOption(
                icon: "photo.on.rectangle",
                label: "Gallery",
                action: onGalleryTap
            )

            AttachmentOption(
                icon: "camera",
                label: "Camera",
                action: onCameraTap
            )

            AttachmentOption(
                icon: "doc",
                label: "File",
                action: onFileTap
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

struct AttachmentOption: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())

                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
