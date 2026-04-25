import Foundation

/// Represents a file attachment in a message.
public struct Attachment: Codable, Equatable {
    public let url: String
    public let mimeType: String?
    public let name: String?
    public let size: Int?

    public init(url: String, mimeType: String? = nil, name: String? = nil, size: Int? = nil) {
        self.url = url
        self.mimeType = mimeType
        self.name = name
        self.size = size
    }
}
