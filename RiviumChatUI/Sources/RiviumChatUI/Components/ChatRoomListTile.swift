import SwiftUI
import RiviumChat

/// List tile for displaying a chat room
public struct ChatRoomListTile: View {
    let room: Room
    var lastMessage: Message? = nil
    var unreadCount: Int = 0
    var isMuted: Bool = false
    var isPinned: Bool = false
    var isTyping: Bool = false
    var isOnline: Bool = false
    let onTap: () -> Void
    var avatar: AnyView? = nil
    var title: AnyView? = nil
    var subtitle: AnyView? = nil
    var trailing: AnyView? = nil

    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions

    public init(
        room: Room,
        lastMessage: Message? = nil,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        isPinned: Bool = false,
        isTyping: Bool = false,
        isOnline: Bool = false,
        onTap: @escaping () -> Void,
        @ViewBuilder avatar: () -> some View = { EmptyView() },
        @ViewBuilder title: () -> some View = { EmptyView() },
        @ViewBuilder subtitle: () -> some View = { EmptyView() },
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) {
        self.room = room
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isTyping = isTyping
        self.isOnline = isOnline
        self.onTap = onTap

        let avatarView = avatar()
        self.avatar = (avatarView is EmptyView) ? nil : AnyView(avatarView)

        let titleView = title()
        self.title = (titleView is EmptyView) ? nil : AnyView(titleView)

        let subtitleView = subtitle()
        self.subtitle = (subtitleView is EmptyView) ? nil : AnyView(subtitleView)

        let trailingView = trailing()
        self.trailing = (trailingView is EmptyView) ? nil : AnyView(trailingView)
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let avatar = avatar {
                        avatar
                    } else {
                        defaultAvatar
                    }

                    if isOnline {
                        PresenceIndicator(isOnline: true, size: 14)
                            .offset(x: 2, y: 2)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    // Title row
                    HStack(spacing: 4) {
                        if let title = title {
                            title
                        } else {
                            Text(room.name ?? "Chat")
                                .font(.body)
                                .fontWeight(unreadCount > 0 ? .semibold : .regular)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Subtitle
                    if let subtitle = subtitle {
                        subtitle
                    } else if isTyping {
                        HStack(spacing: 4) {
                            TypingDots(dotSize: 6, dotSpacing: 2)
                            Text("typing...")
                                .font(.caption)
                                .foregroundColor(colors.typingIndicator)
                        }
                    } else {
                        Text(lastMessageText)
                            .font(.caption)
                            .foregroundColor(unreadCount > 0 ? .primary : .secondary)
                            .fontWeight(unreadCount > 0 ? .medium : .regular)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Trailing
                if let trailing = trailing {
                    trailing
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let timestamp = lastMessage?.createdAt {
                            Text(formatTimestamp(timestamp))
                                .font(.caption2)
                                .foregroundColor(unreadCount > 0 ? .accentColor : .secondary)
                        }

                        if unreadCount > 0 {
                            UnreadBadge(
                                count: unreadCount,
                                backgroundColor: isMuted ? .secondary : nil
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPinned ? Color(UIColor.systemGray6).opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: dimensions.avatarSize, height: dimensions.avatarSize)
            .overlay(
                Text(String((room.name ?? "?").prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.accentColor)
            )
    }

    private var lastMessageText: String {
        guard let message = lastMessage else {
            return "No messages yet"
        }

        switch message.type {
        case .image:
            return "📷 Photo"
        case .file:
            return "📎 File"
        case .system:
            return message.content
        default:
            return message.content
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            return dayFormatter.string(from: date)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yy"
            return dateFormatter.string(from: date)
        }
    }
}

/// Skeleton placeholder for loading state
public struct ChatRoomListTileSkeleton: View {
    @Environment(\.riviumChatDimensions) private var dimensions

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(UIColor.systemGray5))
                .frame(width: dimensions.avatarSize, height: dimensions.avatarSize)

            VStack(alignment: .leading, spacing: 8) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 120, height: 16)

                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 180, height: 12)
            }

            Spacer()

            // Timestamp skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(UIColor.systemGray5))
                .frame(width: 40, height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
