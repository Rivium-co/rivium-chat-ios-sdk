import SwiftUI
import RiviumChat

/// Actions available in the message context menu
public enum MessageAction: CaseIterable {
    case reply
    case copy
    case edit
    case delete
    case pin
    case react
}

/// Context menu for message actions
public struct MessageContextMenu: View {
    let message: Message
    let isMe: Bool
    var isPinned: Bool = false
    let onAction: (MessageAction) -> Void
    var availableActions: [MessageAction]? = nil

    public init(
        message: Message,
        isMe: Bool,
        isPinned: Bool = false,
        onAction: @escaping (MessageAction) -> Void,
        availableActions: [MessageAction]? = nil
    ) {
        self.message = message
        self.isMe = isMe
        self.isPinned = isPinned
        self.onAction = onAction
        self.availableActions = availableActions
    }

    private var actions: [MessageAction] {
        availableActions ?? defaultActions
    }

    private var defaultActions: [MessageAction] {
        if isMe {
            return [.reply, .copy, .edit, .delete, .pin, .react]
        } else {
            return [.reply, .copy, .pin, .react]
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                ContextMenuItem(
                    action: action,
                    isPinned: isPinned,
                    onTap: { onAction(action) }
                )

                if index < actions.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct ContextMenuItem: View {
    let action: MessageAction
    var isPinned: Bool = false
    let onTap: () -> Void

    private var icon: String {
        switch action {
        case .reply: return "arrowshape.turn.up.left"
        case .copy: return "doc.on.doc"
        case .edit: return "pencil"
        case .delete: return "trash"
        case .pin: return isPinned ? "pin.slash" : "pin"
        case .react: return "face.smiling"
        }
    }

    private var label: String {
        switch action {
        case .reply: return "Reply"
        case .copy: return "Copy"
        case .edit: return "Edit"
        case .delete: return "Delete"
        case .pin: return isPinned ? "Unpin" : "Pin"
        case .react: return "React"
        }
    }

    private var isDestructive: Bool {
        action == .delete
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 20)

                Text(label)
                    .font(.body)

                Spacer()
            }
            .foregroundColor(isDestructive ? .red : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Modifier for adding context menu to messages
public extension View {
    func messageContextMenu(
        message: Message,
        isMe: Bool,
        isPinned: Bool = false,
        onAction: @escaping (MessageAction) -> Void
    ) -> some View {
        self.contextMenu {
            Button {
                onAction(.reply)
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }

            Button {
                onAction(.copy)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if isMe {
                Button {
                    onAction(.edit)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Button {
                onAction(.pin)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Button {
                onAction(.react)
            } label: {
                Label("React", systemImage: "face.smiling")
            }

            if isMe {
                Divider()

                Button(role: .destructive) {
                    onAction(.delete)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
