import SwiftUI

/// Default commonly used reactions
public let defaultReactions = ["❤️", "👍", "👎", "😂", "😮", "😢"]

/// Quick reaction picker with common emojis
public struct MessageReactionPicker: View {
    let onReactionSelected: (String) -> Void
    var onMoreTap: (() -> Void)? = nil
    var commonReactions: [String] = defaultReactions

    public init(
        onReactionSelected: @escaping (String) -> Void,
        onMoreTap: (() -> Void)? = nil,
        commonReactions: [String] = defaultReactions
    ) {
        self.onReactionSelected = onReactionSelected
        self.onMoreTap = onMoreTap
        self.commonReactions = commonReactions
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(commonReactions, id: \.self) { emoji in
                ReactionButton(emoji: emoji) {
                    onReactionSelected(emoji)
                }
            }

            if let onMoreTap = onMoreTap {
                Button(action: onMoreTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

struct ReactionButton: View {
    let emoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}

/// Display reactions on a message
public struct MessageReactions: View {
    let reactions: [String: Int]
    var userReactions: Set<String> = []
    let onReactionTap: (String) -> Void

    public init(
        reactions: [String: Int],
        userReactions: Set<String> = [],
        onReactionTap: @escaping (String) -> Void
    ) {
        self.reactions = reactions
        self.userReactions = userReactions
        self.onReactionTap = onReactionTap
    }

    public var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(reactions.keys), id: \.self) { emoji in
                    ReactionChip(
                        emoji: emoji,
                        count: reactions[emoji] ?? 0,
                        isSelected: userReactions.contains(emoji),
                        onTap: { onReactionTap(emoji) }
                    )
                }
            }
        }
    }
}

struct ReactionChip: View {
    let emoji: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.caption)
                if count > 1 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(UIColor.systemGray5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
