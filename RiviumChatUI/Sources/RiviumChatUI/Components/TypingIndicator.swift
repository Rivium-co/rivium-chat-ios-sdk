import SwiftUI

/// Displays a typing indicator when users are typing
public struct TypingIndicator: View {
    let typingUsers: [String]
    var userDisplayNames: [String: String] = [:]

    @Environment(\.riviumChatColors) private var colors
    @Environment(\.riviumChatDimensions) private var dimensions

    public init(
        typingUsers: [String],
        userDisplayNames: [String: String] = [:]
    ) {
        self.typingUsers = typingUsers
        self.userDisplayNames = userDisplayNames
    }

    public var body: some View {
        if typingUsers.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer().frame(width: dimensions.smallAvatarSize + 8)

                HStack(spacing: 8) {
                    TypingDots()

                    Text(displayText)
                        .font(.caption)
                        .foregroundColor(colors.typingIndicator)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(colors.otherMessageBubble)
                .clipShape(RoundedRectangle(cornerRadius: dimensions.messageBubbleRadius))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var displayText: String {
        switch typingUsers.count {
        case 1:
            let name = userDisplayNames[typingUsers[0]] ?? typingUsers[0]
            return "\(name) is typing..."
        case 2:
            let name1 = userDisplayNames[typingUsers[0]] ?? typingUsers[0]
            let name2 = userDisplayNames[typingUsers[1]] ?? typingUsers[1]
            return "\(name1) and \(name2) are typing..."
        default:
            return "\(typingUsers.count) people are typing..."
        }
    }
}

/// Animated typing dots
public struct TypingDots: View {
    @State private var animationOffset: CGFloat = 0
    var dotCount: Int = 3
    var dotSize: CGFloat = 8
    var dotSpacing: CGFloat = 4

    @Environment(\.riviumChatColors) private var colors

    public init(
        dotCount: Int = 3,
        dotSize: CGFloat = 8,
        dotSpacing: CGFloat = 4
    ) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.dotSpacing = dotSpacing
    }

    public var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(colors.typingIndicator)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animationOffset(for: index))
                    .animation(
                        Animation
                            .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = -4
        }
    }

    private func animationOffset(for index: Int) -> CGFloat {
        return animationOffset
    }
}

/// Compact typing indicator showing just dots
public struct CompactTypingIndicator: View {
    let isTyping: Bool

    @Environment(\.riviumChatColors) private var colors

    public init(isTyping: Bool) {
        self.isTyping = isTyping
    }

    public var body: some View {
        if isTyping {
            TypingDots()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(colors.otherMessageBubble)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
