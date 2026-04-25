import SwiftUI

/// A user that can be mentioned in a message.
public struct MentionUser: Identifiable {
    public let id: String
    public let displayName: String
    public let avatarUrl: String?
    public let isOnline: Bool

    public init(id: String, displayName: String, avatarUrl: String? = nil, isOnline: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isOnline = isOnline
    }
}

/// A view that displays an autocomplete list for @mentions.
public struct MentionsList: View {
    let users: [MentionUser]
    let query: String
    let onUserSelected: (MentionUser) -> Void
    var maxSuggestions: Int = 5
    var backgroundColor: Color?

    @Environment(\.riviumChatColors) private var colors

    public init(
        users: [MentionUser],
        query: String,
        onUserSelected: @escaping (MentionUser) -> Void,
        maxSuggestions: Int = 5,
        backgroundColor: Color? = nil
    ) {
        self.users = users
        self.query = query
        self.onUserSelected = onUserSelected
        self.maxSuggestions = maxSuggestions
        self.backgroundColor = backgroundColor
    }

    private var filteredUsers: [MentionUser] {
        if query.isEmpty {
            return Array(users.prefix(maxSuggestions))
        }
        let lowercasedQuery = query.lowercased()
        return users
            .filter { $0.displayName.lowercased().contains(lowercasedQuery) }
            .prefix(maxSuggestions)
            .map { $0 }
    }

    public var body: some View {
        if !filteredUsers.isEmpty {
            VStack(spacing: 0) {
                ForEach(filteredUsers) { user in
                    MentionUserTile(user: user, query: query) {
                        onUserSelected(user)
                    }

                    if user.id != filteredUsers.last?.id {
                        Divider()
                    }
                }
            }
            .background(backgroundColor ?? Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
}

struct MentionUserTile: View {
    let user: MentionUser
    let query: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar with online indicator
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(user.displayName.prefix(1)).uppercased())
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                        )

                    if user.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                            )
                    }
                }

                // Name with highlighted query
                HighlightedText(text: user.displayName, query: query)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        if query.isEmpty {
            Text(text)
        } else {
            highlightedTextView
        }
    }

    private var highlightedTextView: some View {
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        if let range = lowercasedText.range(of: lowercasedQuery) {
            let startIndex = text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound))
            let endIndex = text.index(startIndex, offsetBy: query.count)

            let before = String(text[..<startIndex])
            let match = String(text[startIndex..<endIndex])
            let after = String(text[endIndex...])

            return Text(before) +
                   Text(match).fontWeight(.bold).foregroundColor(.accentColor) +
                   Text(after)
        } else {
            return Text(text)
        }
    }
}

/// Controller to manage mentions in a text input.
public class MentionsController: ObservableObject {
    @Published public private(set) var currentQuery: String?
    @Published public private(set) var mentionStartIndex: String.Index?

    private let availableUsers: [MentionUser]

    public init(availableUsers: [MentionUser]) {
        self.availableUsers = availableUsers
    }

    public var isMentioning: Bool {
        currentQuery != nil
    }

    /// Call this when the text changes to update mention state.
    public func onTextChanged(text: String, cursorPosition: Int) {
        guard cursorPosition > 0, cursorPosition <= text.count else {
            currentQuery = nil
            mentionStartIndex = nil
            return
        }

        let cursorIndex = text.index(text.startIndex, offsetBy: cursorPosition)
        let textBeforeCursor = String(text[..<cursorIndex])

        guard let lastAtIndex = textBeforeCursor.lastIndex(of: "@") else {
            currentQuery = nil
            mentionStartIndex = nil
            return
        }

        let afterAt = String(textBeforeCursor[textBeforeCursor.index(after: lastAtIndex)...])

        // Check if there's a space after @
        if afterAt.contains(" ") || afterAt.contains("\n") {
            currentQuery = nil
            mentionStartIndex = nil
            return
        }

        // Check if @ is at start or preceded by space
        if lastAtIndex != textBeforeCursor.startIndex {
            let charBefore = textBeforeCursor[textBeforeCursor.index(before: lastAtIndex)]
            if charBefore != " " && charBefore != "\n" {
                currentQuery = nil
                mentionStartIndex = nil
                return
            }
        }

        mentionStartIndex = lastAtIndex
        currentQuery = afterAt
    }

    /// Insert a mention into the text.
    public func insertMention(text: String, cursorPosition: Int, user: MentionUser) -> (String, Int) {
        guard let startIndex = mentionStartIndex else {
            return (text, cursorPosition)
        }

        let cursorIndex = text.index(text.startIndex, offsetBy: min(cursorPosition, text.count))
        let beforeMention = String(text[..<startIndex])
        let afterMention = String(text[cursorIndex...])

        let mentionText = "@\(user.displayName) "
        let newText = beforeMention + mentionText + afterMention
        let newCursorPosition = beforeMention.count + mentionText.count

        currentQuery = nil
        mentionStartIndex = nil

        return (newText, newCursorPosition)
    }

    /// Clear the current mention state.
    public func clear() {
        currentQuery = nil
        mentionStartIndex = nil
    }
}
