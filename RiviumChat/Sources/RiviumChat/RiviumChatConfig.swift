import Foundation

/// Result of a file upload operation.
public struct FileUploadResult {
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

    /// Converts to an Attachment for use in messages.
    public func toAttachment() -> Attachment {
        Attachment(url: url, mimeType: mimeType, name: name, size: size)
    }
}

/// Callback type for uploading files.
///
/// Implement this to integrate with your storage service (S3, Firebase, Supabase, etc.).
public typealias FileUploader = (URL) async throws -> FileUploadResult

/// Returns a user token for the current user, issued by your server.
///
/// Your server calls `POST https://chat.rivium.co/api/v1/users/token` with the
/// `x-server-secret` header (Node SDK: `chat.users.createToken`) and returns
/// the token to the app. Never put the server secret in the app.
public typealias ChatTokenProvider = () async throws -> String

/// Configuration for RiviumChat SDK.
public struct RiviumChatConfig {
    /// Base URL for the RiviumChat API
    public static let baseUrl = "https://chat.rivium.co"

    /// WebSocket URL for Centrifugo realtime server
    public static let centrifugoUrl = "wss://ws-chat.rivium.co/connection/websocket"

    /// Your RiviumChat API key
    public let apiKey: String

    /// The external user ID for the current user
    public let userId: String

    /// Optional user info (displayName, locale, etc.)
    public let userInfo: [String: String]?

    /// Optional file uploader callback for sending attachments.
    public let fileUploader: FileUploader?

    /// Recommended. Proves who the user is: every request carries a token your
    /// server issued, so nobody holding the public ``apiKey`` can act as
    /// another user. Called on connect, shortly before the token expires, and
    /// when the server reports an expired token — refreshes are invisible to
    /// the user.
    ///
    /// Without it the SDK uses the legacy mode (API key + ``userId``), which a
    /// project can disable in Rivium Console.
    public let tokenProvider: ChatTokenProvider?

    public init(
        apiKey: String,
        userId: String,
        userInfo: [String: String]? = nil,
        fileUploader: FileUploader? = nil,
        tokenProvider: ChatTokenProvider? = nil
    ) {
        precondition(!apiKey.isEmpty, "API key cannot be empty")
        precondition(!userId.isEmpty, "User ID cannot be empty")

        self.apiKey = apiKey
        self.userId = userId
        self.userInfo = userInfo
        self.fileUploader = fileUploader
        self.tokenProvider = tokenProvider
    }
}
