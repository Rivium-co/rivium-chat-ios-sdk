import SwiftUI
import RiviumChat

/// Represents a user who has read a message.
public struct ReadReceiptUser: Identifiable {
    public let id: String
    public let displayName: String?
    public let avatarUrl: String?
    public let readAt: Date

    public init(id: String, displayName: String? = nil, avatarUrl: String? = nil, readAt: Date) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.readAt = readAt
    }
}

/// Message delivery and read status.
public enum MessageDeliveryStatus {
    case sending
    case sent
    case delivered
    case read
    case failed
}

/// A view that displays read receipts for a message.
public struct ReadReceipts: View {
    let status: MessageDeliveryStatus
    var readBy: [ReadReceiptUser]?
    var showAvatars: Bool = false
    var maxAvatars: Int = 3
    var iconSize: CGFloat = 16
    var avatarSize: CGFloat = 14
    var readColor: Color?
    var sentColor: Color?
    var failedColor: Color?
    var onTap: (() -> Void)?

    @Environment(\.riviumChatColors) private var colors

    public init(
        status: MessageDeliveryStatus,
        readBy: [ReadReceiptUser]? = nil,
        showAvatars: Bool = false,
        maxAvatars: Int = 3,
        iconSize: CGFloat = 16,
        avatarSize: CGFloat = 14,
        readColor: Color? = nil,
        sentColor: Color? = nil,
        failedColor: Color? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.status = status
        self.readBy = readBy
        self.showAvatars = showAvatars
        self.maxAvatars = maxAvatars
        self.iconSize = iconSize
        self.avatarSize = avatarSize
        self.readColor = readColor
        self.sentColor = sentColor
        self.failedColor = failedColor
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if showAvatars, let users = readBy, !users.isEmpty {
                avatarReceipts(users: users)
            } else {
                checkmarkReceipts
            }
        }
        .onTapGesture {
            onTap?()
        }
    }

    private var checkmarkReceipts: some View {
        let (imageName, color) = statusImageAndColor

        return Image(systemName: imageName)
            .font(.system(size: iconSize * 0.8))
            .foregroundColor(color)
    }

    private var statusImageAndColor: (String, Color) {
        let defaultSentColor = sentColor ?? Color.secondary
        let defaultReadColor = readColor ?? colors.readReceipt
        let defaultFailedColor = failedColor ?? colors.failedMessage

        switch status {
        case .sending:
            return ("clock", defaultSentColor)
        case .sent:
            return ("checkmark", defaultSentColor)
        case .delivered:
            return ("checkmark.circle", defaultSentColor)
        case .read:
            return ("checkmark.circle.fill", defaultReadColor)
        case .failed:
            return ("exclamationmark.circle", defaultFailedColor)
        }
    }

    private func avatarReceipts(users: [ReadReceiptUser]) -> some View {
        let displayUsers = Array(users.prefix(maxAvatars))
        let remaining = users.count - maxAvatars

        return HStack(spacing: -avatarSize * 0.4) {
            ForEach(displayUsers) { user in
                avatarView(for: user)
            }

            if remaining > 0 {
                Text("+\(remaining)")
                    .font(.system(size: avatarSize * 0.6))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func avatarView(for user: ReadReceiptUser) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.3))
            .frame(width: avatarSize, height: avatarSize)
            .overlay(
                Text(String((user.displayName ?? "?").prefix(1)).uppercased())
                    .font(.system(size: avatarSize * 0.4))
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            )
            .overlay(
                Circle()
                    .stroke(Color(UIColor.systemBackground), lineWidth: 1)
            )
    }
}

/// A sheet that shows detailed read receipt information.
public struct ReadReceiptDetails: View {
    let readBy: [ReadReceiptUser]
    var sentAt: Date?
    var deliveredAt: Date?
    @Binding var isPresented: Bool

    public init(
        readBy: [ReadReceiptUser],
        sentAt: Date? = nil,
        deliveredAt: Date? = nil,
        isPresented: Binding<Bool>
    ) {
        self.readBy = readBy
        self.sentAt = sentAt
        self.deliveredAt = deliveredAt
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationView {
            List {
                // Status section
                if sentAt != nil || deliveredAt != nil {
                    Section("Status") {
                        if let sentAt = sentAt {
                            statusRow(icon: "checkmark", label: "Sent", time: sentAt)
                        }
                        if let deliveredAt = deliveredAt {
                            statusRow(icon: "checkmark.circle", label: "Delivered", time: deliveredAt)
                        }
                    }
                }

                // Read by section
                if !readBy.isEmpty {
                    Section("Read by \(readBy.count)") {
                        ForEach(readBy) { user in
                            readByRow(user: user)
                        }
                    }
                }
            }
            .navigationTitle("Message Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func statusRow(icon: String, label: String, time: Date) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(label)
            Spacer()
            Text(formatTime(time))
                .foregroundColor(.secondary)
        }
    }

    private func readByRow(user: ReadReceiptUser) -> some View {
        HStack {
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String((user.displayName ?? "?").prefix(1)).uppercased())
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                )

            Text(user.displayName ?? "Unknown")
            Spacer()
            Text(formatTime(user.readAt))
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM/yyyy, HH:mm"
        }
        return formatter.string(from: date)
    }
}
