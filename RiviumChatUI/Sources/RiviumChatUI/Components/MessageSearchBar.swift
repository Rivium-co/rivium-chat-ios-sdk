import SwiftUI
import RiviumChat

/// A search bar with navigation for searching messages.
public struct MessageSearchBar: View {
    @Binding var searchText: String
    @Binding var currentIndex: Int
    let totalResults: Int
    var onSearch: ((String) -> Void)?
    var onNavigatePrevious: (() -> Void)?
    var onNavigateNext: (() -> Void)?
    var onClose: (() -> Void)?
    var placeholder: String = "Search messages"

    @FocusState private var isFocused: Bool

    public init(
        searchText: Binding<String>,
        currentIndex: Binding<Int>,
        totalResults: Int,
        onSearch: ((String) -> Void)? = nil,
        onNavigatePrevious: (() -> Void)? = nil,
        onNavigateNext: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        placeholder: String = "Search messages"
    ) {
        self._searchText = searchText
        self._currentIndex = currentIndex
        self.totalResults = totalResults
        self.onSearch = onSearch
        self.onNavigatePrevious = onNavigatePrevious
        self.onNavigateNext = onNavigateNext
        self.onClose = onClose
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        onSearch?(searchText)
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            // Results count and navigation
            if totalResults > 0 {
                HStack(spacing: 4) {
                    Text("\(currentIndex + 1)/\(totalResults)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()

                    Button(action: { onNavigatePrevious?() }) {
                        Image(systemName: "chevron.up")
                            .foregroundColor(currentIndex > 0 ? .accentColor : .secondary)
                    }
                    .disabled(currentIndex <= 0)

                    Button(action: { onNavigateNext?() }) {
                        Image(systemName: "chevron.down")
                            .foregroundColor(currentIndex < totalResults - 1 ? .accentColor : .secondary)
                    }
                    .disabled(currentIndex >= totalResults - 1)
                }
            }

            // Close button
            if let onClose = onClose {
                Button(action: onClose) {
                    Text("Cancel")
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isFocused = true
        }
    }
}

/// An overlay that displays search functionality for messages.
public struct MessageSearchOverlay: View {
    let messages: [Message]
    let onMessageSelected: (Message) -> Void
    let onClose: () -> Void
    var getSenderName: ((String) -> String)?

    @State private var searchText = ""
    @State private var searchResults: [Message] = []
    @State private var currentIndex = 0

    public init(
        messages: [Message],
        onMessageSelected: @escaping (Message) -> Void,
        onClose: @escaping () -> Void,
        getSenderName: ((String) -> String)? = nil
    ) {
        self.messages = messages
        self.onMessageSelected = onMessageSelected
        self.onClose = onClose
        self.getSenderName = getSenderName
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            MessageSearchBar(
                searchText: $searchText,
                currentIndex: $currentIndex,
                totalResults: searchResults.count,
                onSearch: { _ in performSearch() },
                onNavigatePrevious: navigatePrevious,
                onNavigateNext: navigateNext,
                onClose: onClose
            )

            Divider()

            // Results list
            if !searchResults.isEmpty {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, message in
                            SearchResultRow(
                                message: message,
                                query: searchText,
                                senderName: getSenderName?(message.senderUserId),
                                isSelected: index == currentIndex
                            )
                            .id(index)
                            .onTapGesture {
                                currentIndex = index
                                onMessageSelected(message)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: currentIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            } else if !searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(UIColor.systemBackground))
        .onChange(of: searchText) { _ in
            performSearch()
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            currentIndex = 0
            return
        }

        let lowercasedQuery = searchText.lowercased()
        searchResults = messages.filter { message in
            message.content.lowercased().contains(lowercasedQuery)
        }
        currentIndex = 0
    }

    private func navigatePrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            if !searchResults.isEmpty {
                onMessageSelected(searchResults[currentIndex])
            }
        }
    }

    private func navigateNext() {
        if currentIndex < searchResults.count - 1 {
            currentIndex += 1
            if !searchResults.isEmpty {
                onMessageSelected(searchResults[currentIndex])
            }
        }
    }
}

struct SearchResultRow: View {
    let message: Message
    let query: String
    let senderName: String?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderName ?? message.senderUserId)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(formatDate(message.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HighlightedSearchText(text: message.content, query: query)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            dateFormatter.dateFormat = "HH:mm"
        } else {
            dateFormatter.dateFormat = "MMM d"
        }
        return dateFormatter.string(from: date)
    }
}

/// Text view with highlighted search matches.
public struct HighlightedSearchText: View {
    let text: String
    let query: String
    var highlightColor: Color = .yellow

    public init(text: String, query: String, highlightColor: Color = .yellow) {
        self.text = text
        self.query = query
        self.highlightColor = highlightColor
    }

    public var body: some View {
        if query.isEmpty {
            Text(text)
        } else {
            highlightedText
        }
    }

    private var highlightedText: Text {
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        var result = Text("")
        var currentIndex = text.startIndex

        while let range = lowercasedText[currentIndex...].range(of: lowercasedQuery) {
            let actualStartIndex = text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound))
            let actualEndIndex = text.index(actualStartIndex, offsetBy: query.count)

            // Add text before match
            if currentIndex < actualStartIndex {
                result = result + Text(String(text[currentIndex..<actualStartIndex]))
            }

            // Add highlighted match
            result = result + Text(String(text[actualStartIndex..<actualEndIndex]))
                .foregroundColor(.primary)
                .fontWeight(.semibold)

            currentIndex = actualEndIndex
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(String(text[currentIndex...]))
        }

        return result
    }
}
