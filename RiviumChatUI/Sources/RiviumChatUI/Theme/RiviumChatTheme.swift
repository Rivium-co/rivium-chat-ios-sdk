import SwiftUI
import UIKit

/// RiviumChat-specific colors
public struct RiviumChatColors {
    public var myMessageBubble: Color
    public var otherMessageBubble: Color
    public var myMessageText: Color
    public var otherMessageText: Color
    public var timestampText: Color
    public var linkText: Color
    public var onlineIndicator: Color
    public var offlineIndicator: Color
    public var typingIndicator: Color
    public var readReceipt: Color
    public var unreadReceipt: Color
    public var failedMessage: Color
    public var pendingMessage: Color
    public var replyBackground: Color
    public var mentionHighlight: Color

    public init(
        myMessageBubble: Color = Color(red: 0, green: 0.478, blue: 1),
        otherMessageBubble: Color = Color(UIColor.systemGray5),
        myMessageText: Color = .white,
        otherMessageText: Color = .primary,
        timestampText: Color = .secondary,
        linkText: Color = Color(red: 0, green: 0.478, blue: 1),
        onlineIndicator: Color = Color(red: 0.204, green: 0.78, blue: 0.349),
        offlineIndicator: Color = Color(UIColor.systemGray3),
        typingIndicator: Color = .secondary,
        readReceipt: Color = Color(red: 0, green: 0.478, blue: 1),
        unreadReceipt: Color = .secondary,
        failedMessage: Color = Color(red: 1, green: 0.231, blue: 0.188),
        pendingMessage: Color = .secondary,
        replyBackground: Color = Color(UIColor.secondarySystemBackground),
        mentionHighlight: Color = Color(red: 0, green: 0.478, blue: 1).opacity(0.2)
    ) {
        self.myMessageBubble = myMessageBubble
        self.otherMessageBubble = otherMessageBubble
        self.myMessageText = myMessageText
        self.otherMessageText = otherMessageText
        self.timestampText = timestampText
        self.linkText = linkText
        self.onlineIndicator = onlineIndicator
        self.offlineIndicator = offlineIndicator
        self.typingIndicator = typingIndicator
        self.readReceipt = readReceipt
        self.unreadReceipt = unreadReceipt
        self.failedMessage = failedMessage
        self.pendingMessage = pendingMessage
        self.replyBackground = replyBackground
        self.mentionHighlight = mentionHighlight
    }

    public static let light = RiviumChatColors()

    public static let dark = RiviumChatColors(
        myMessageBubble: Color(red: 0.039, green: 0.518, blue: 1),
        otherMessageBubble: Color(UIColor.secondarySystemBackground),
        myMessageText: .white,
        otherMessageText: .white,
        onlineIndicator: Color(red: 0.188, green: 0.82, blue: 0.345),
        offlineIndicator: Color(UIColor.systemGray),
        failedMessage: Color(red: 1, green: 0.271, blue: 0.227),
        replyBackground: Color(UIColor.tertiarySystemBackground)
    )
}

/// RiviumChat-specific dimensions
public struct RiviumChatDimensions {
    public var messageBubbleRadius: CGFloat
    public var messagePadding: CGFloat
    public var avatarSize: CGFloat
    public var smallAvatarSize: CGFloat
    public var inputFieldRadius: CGFloat
    public var maxBubbleWidthRatio: CGFloat
    public var imagePreviewSize: CGFloat
    public var reactionPillRadius: CGFloat

    public init(
        messageBubbleRadius: CGFloat = 16,
        messagePadding: CGFloat = 12,
        avatarSize: CGFloat = 40,
        smallAvatarSize: CGFloat = 24,
        inputFieldRadius: CGFloat = 24,
        maxBubbleWidthRatio: CGFloat = 0.75,
        imagePreviewSize: CGFloat = 200,
        reactionPillRadius: CGFloat = 12
    ) {
        self.messageBubbleRadius = messageBubbleRadius
        self.messagePadding = messagePadding
        self.avatarSize = avatarSize
        self.smallAvatarSize = smallAvatarSize
        self.inputFieldRadius = inputFieldRadius
        self.maxBubbleWidthRatio = maxBubbleWidthRatio
        self.imagePreviewSize = imagePreviewSize
        self.reactionPillRadius = reactionPillRadius
    }
}

/// Environment key for RiviumChatColors
private struct RiviumChatColorsKey: EnvironmentKey {
    static let defaultValue = RiviumChatColors()
}

/// Environment key for RiviumChatDimensions
private struct RiviumChatDimensionsKey: EnvironmentKey {
    static let defaultValue = RiviumChatDimensions()
}

extension EnvironmentValues {
    public var riviumChatColors: RiviumChatColors {
        get { self[RiviumChatColorsKey.self] }
        set { self[RiviumChatColorsKey.self] = newValue }
    }

    public var riviumChatDimensions: RiviumChatDimensions {
        get { self[RiviumChatDimensionsKey.self] }
        set { self[RiviumChatDimensionsKey.self] = newValue }
    }
}

/// Theme wrapper for RiviumChat UI components
public struct RiviumChatTheme<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let colors: RiviumChatColors?
    private let dimensions: RiviumChatDimensions
    private let content: () -> Content

    public init(
        colors: RiviumChatColors? = nil,
        dimensions: RiviumChatDimensions = RiviumChatDimensions(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.colors = colors
        self.dimensions = dimensions
        self.content = content
    }

    public var body: some View {
        let resolvedColors = colors ?? (colorScheme == .dark ? .dark : .light)
        content()
            .environment(\.riviumChatColors, resolvedColors)
            .environment(\.riviumChatDimensions, dimensions)
    }
}
