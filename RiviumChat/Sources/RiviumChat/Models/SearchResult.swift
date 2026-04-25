import Foundation

/// Result of a message search query.
public struct SearchResult: Codable {
    public let messages: [Message]
    public let total: Int
    public let hasMore: Bool

    public init(messages: [Message], total: Int, hasMore: Bool) {
        self.messages = messages
        self.total = total
        self.hasMore = hasMore
    }
}

/// Result of a file upload.
public struct UploadResult: Codable {
    public let url: String
    public let mimeType: String
    public let size: Int
    public let name: String

    public init(url: String, mimeType: String, size: Int, name: String) {
        self.url = url
        self.mimeType = mimeType
        self.size = size
        self.name = name
    }
}
