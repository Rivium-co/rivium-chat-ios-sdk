import Foundation

/// HTTP API service for RiviumChat backend.
public class ApiService {
    private let config: RiviumChatConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Set by ``RiviumChatClient`` so identity failures reach the app.
    var onAuthError: ((AuthErrorEvent) -> Void)?

    private let tokens: TokenManager?

    public init(config: RiviumChatConfig) {
        self.config = config
        self.tokens = config.tokenProvider.map { TokenManager(provider: $0) }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Room Operations

    /// Creates a new chat room.
    public func createRoom(
        type: RoomType = .direct,
        name: String? = nil,
        participants: [[String: Any]],
        metadata: [String: Any]? = nil
    ) async throws -> Room {
        var body: [String: Any] = [
            "type": type.rawValue,
            "participants": participants
        ]
        if let name = name {
            body["name"] = name
        }
        if let metadata = metadata {
            body["metadata"] = metadata
        }

        let data = try await request(method: "POST", path: "/api/v1/rooms", body: body)
        return try decoder.decode(Room.self, from: data)
    }

    /// Find or create a room by external ID.
    public func findOrCreateRoom(
        externalId: String,
        type: RoomType = .direct,
        name: String? = nil,
        participants: [[String: Any]],
        metadata: [String: Any]? = nil
    ) async throws -> Room {
        var body: [String: Any] = [
            "externalId": externalId,
            "type": type.rawValue,
            "participants": participants
        ]
        if let name = name {
            body["name"] = name
        }
        if let metadata = metadata {
            body["metadata"] = metadata
        }

        let data = try await request(
            method: "POST",
            path: "/api/v1/rooms/find-or-create",
            body: body
        )
        // API returns { room: {...}, created: bool }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let roomJson = json["room"] as? [String: Any] {
            let roomData = try JSONSerialization.data(withJSONObject: roomJson)
            return try decoder.decode(Room.self, from: roomData)
        }
        return try decoder.decode(Room.self, from: data)
    }

    /// Gets a room by its external ID.
    public func getRoomByExternalId(_ externalId: String) async throws -> Room {
        let encodedId = externalId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? externalId
        let data = try await request(method: "GET", path: "/api/v1/rooms/by-external-id/\(encodedId)")
        return try decoder.decode(Room.self, from: data)
    }

    /// List all rooms for a user.
    public func listRooms(_ userId: String) async throws -> [Room] {
        let data = try await request(method: "GET", path: "/api/v1/rooms?userId=\(userId)")
        return try decoder.decode([Room].self, from: data)
    }

    /// Get a room by ID.
    public func getRoom(_ roomId: String) async throws -> Room {
        let data = try await request(method: "GET", path: "/api/v1/rooms/\(roomId)")
        return try decoder.decode(Room.self, from: data)
    }

    /// Adds a participant to a room.
    public func addParticipant(
        _ roomId: String,
        externalUserId: String,
        displayName: String? = nil,
        locale: String? = nil,
        role: ParticipantRole = .member
    ) async throws -> Participant {
        var body: [String: Any] = [
            "externalUserId": externalUserId,
            "role": role.rawValue
        ]
        if let displayName = displayName {
            body["displayName"] = displayName
        }
        if let locale = locale {
            body["locale"] = locale
        }

        let data = try await request(method: "POST", path: "/api/v1/rooms/\(roomId)/participants", body: body)
        return try decoder.decode(Participant.self, from: data)
    }

    // MARK: - Message Operations

    /// Send a message to a room.
    public func sendMessage(
        _ roomId: String,
        senderUserId: String,
        content: String,
        type: MessageType = .text,
        attachments: [Attachment]? = nil,
        metadata: [String: Any]? = nil,
        replyToId: String? = nil
    ) async throws -> Message {
        var body: [String: Any] = [
            "senderUserId": senderUserId,
            "content": content,
            "type": type.rawValue
        ]
        if let attachments = attachments {
            body["attachments"] = attachments.map { att -> [String: Any] in
                var d: [String: Any] = ["url": att.url]
                if let m = att.mimeType { d["mimeType"] = m }
                if let n = att.name { d["name"] = n }
                if let s = att.size { d["size"] = s }
                return d
            }
        }
        if let metadata = metadata {
            body["metadata"] = metadata
        }
        if let replyToId = replyToId {
            body["replyToId"] = replyToId
        }

        let data = try await request(
            method: "POST",
            path: "/api/v1/rooms/\(roomId)/messages",
            body: body
        )
        return try decoder.decode(Message.self, from: data)
    }

    /// Get messages for a room with pagination.
    public func getMessages(
        _ roomId: String,
        userId: String,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> PaginatedMessages {
        var path = "/api/v1/rooms/\(roomId)/messages?userId=\(userId)&limit=\(limit)"
        if let before = before {
            path += "&before=\(before)"
        }

        let data = try await request(method: "GET", path: path)
        return try decoder.decode(PaginatedMessages.self, from: data)
    }

    /// Marks messages in a room as read.
    public func markAsRead(_ roomId: String, _ userId: String) async throws {
        let body: [String: Any] = ["userId": userId]
        _ = try await request(
            method: "POST",
            path: "/api/v1/rooms/\(roomId)/read",
            body: body
        )
    }

    /// Delete a message.
    public func deleteMessage(_ messageId: String, _ userId: String) async throws {
        _ = try await request(
            method: "DELETE",
            path: "/api/v1/messages/\(messageId)?userId=\(userId)"
        )
    }

    /// Edit a message.
    public func editMessage(
        _ messageId: String,
        userId: String,
        content: String
    ) async throws -> Message {
        let body: [String: Any] = [
            "userId": userId,
            "content": content
        ]
        let data = try await request(
            method: "PUT",
            path: "/api/v1/messages/\(messageId)",
            body: body
        )
        return try decoder.decode(Message.self, from: data)
    }

    /// Search messages in a room.
    public func searchMessages(
        _ roomId: String,
        userId: String,
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/api/v1/rooms/\(roomId)/messages/search?userId=\(userId)&q=\(encodedQuery)&limit=\(limit)&offset=\(offset)"
        let data = try await request(method: "GET", path: path)
        return try decoder.decode([Message].self, from: data)
    }

    // MARK: - Reaction Operations

    /// Add a reaction to a message.
    public func addReaction(
        _ messageId: String,
        userId: String,
        emoji: String
    ) async throws -> Reaction {
        let body: [String: Any] = [
            "userId": userId,
            "emoji": emoji
        ]
        let data = try await request(
            method: "POST",
            path: "/api/v1/messages/\(messageId)/reactions",
            body: body
        )
        return try decoder.decode(Reaction.self, from: data)
    }

    /// Remove a reaction from a message.
    public func removeReaction(
        _ messageId: String,
        userId: String,
        emoji: String
    ) async throws {
        let body: [String: Any] = [
            "userId": userId,
            "emoji": emoji
        ]
        _ = try await request(
            method: "DELETE",
            path: "/api/v1/messages/\(messageId)/reactions",
            body: body
        )
    }

    /// Gets all reactions for a message.
    public func getReactions(_ messageId: String) async throws -> [Reaction] {
        let data = try await request(method: "GET", path: "/api/v1/messages/\(messageId)/reactions")
        return try decoder.decode([Reaction].self, from: data)
    }

    // MARK: - Pin Operations

    /// Pin a message.
    public func pinMessage(_ messageId: String, userId: String) async throws -> Message {
        let body: [String: Any] = ["userId": userId]
        let data = try await request(
            method: "POST",
            path: "/api/v1/messages/\(messageId)/pin",
            body: body
        )
        return try decoder.decode(Message.self, from: data)
    }

    /// Unpin a message.
    public func unpinMessage(_ messageId: String, userId: String) async throws {
        let body: [String: Any] = ["userId": userId]
        _ = try await request(
            method: "DELETE",
            path: "/api/v1/messages/\(messageId)/pin",
            body: body
        )
    }

    /// Get all pinned messages in a room.
    public func getPinnedMessages(_ roomId: String) async throws -> [Message] {
        let data = try await request(method: "GET", path: "/api/v1/rooms/\(roomId)/pinned")
        return try decoder.decode([Message].self, from: data)
    }

    // MARK: - Other Operations

    /// Get unread summary for all rooms.
    public func getUnreadSummary(_ userId: String) async throws -> UnreadSummary {
        let data = try await request(method: "GET", path: "/api/v1/rooms/unread-summary?userId=\(userId)")
        return try decoder.decode(UnreadSummary.self, from: data)
    }

    /// Get messages where a user is mentioned.
    public func getMentions(
        _ roomId: String,
        userId: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [Message] {
        let data = try await request(
            method: "GET",
            path: "/api/v1/rooms/\(roomId)/mentions?userId=\(userId)&limit=\(limit)&offset=\(offset)"
        )
        return try decoder.decode([Message].self, from: data)
    }

    /// Gets a Centrifugo connection token.
    public func getCentrifugoToken(
        _ userId: String,
        info: [String: String]? = nil
    ) async throws -> String {
        var body: [String: Any] = ["userId": userId]
        if let info = info {
            body["info"] = info
        }
        let data = try await request(
            method: "POST",
            path: "/api/v1/centrifugo/token",
            body: body
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw RiviumChatError.decodingError(NSError(domain: "RiviumChat", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing token in response"]))
        }
        return token
    }

    /// Disposes resources.
    public func dispose() {
        session.invalidateAndCancel()
    }

    // MARK: - Private Helpers

    /// A user token for the realtime connection, when a tokenProvider is set.
    func userTokenOrNil() async throws -> String? {
        try await tokens?.get()
    }

    /// Forgets the cached user token (e.g. on logout).
    func clearUserToken() async {
        await tokens?.clear()
    }

    /// Gets a user token, reporting a failing tokenProvider as an auth error.
    private func userToken(_ get: () async throws -> String) async throws -> String {
        do {
            return try await get()
        } catch {
            onAuthError?(AuthErrorEvent(code: "token_provider_failed", message: "tokenProvider failed", error: error))
            throw error
        }
    }

    private func request(method: String, path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: RiviumChatConfig.baseUrl + path) else {
            throw RiviumChatError.invalidURL
        }

        func send(_ userToken: String?) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let userToken {
                request.setValue(userToken, forHTTPHeaderField: "x-user-token")
            }
            if let body = body {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RiviumChatError.invalidResponse
            }
            return (data, httpResponse)
        }

        var data: Data
        var httpResponse: HTTPURLResponse

        if let tokens {
            (data, httpResponse) = try await send(try await userToken { try await tokens.get() })
            // An expired token is routine: fetch a new one and replay the
            // request once. The user never sees it.
            if httpResponse.statusCode == 401, Self.authErrorCode(data) == "token_expired" {
                (data, httpResponse) = try await send(try await userToken { try await tokens.refresh() })
            }
        } else {
            (data, httpResponse) = try await send(nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401, tokens != nil, let code = Self.authErrorCode(data) {
                onAuthError?(AuthErrorEvent(code: code, message: Self.authErrorMessage(data)))
            }
            throw RiviumChatError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }

    /// The identity error code (`token_*`) of a 401 body, if any.
    private static func authErrorCode(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code.hasPrefix("token_") else { return nil }
        return code
    }

    private static func authErrorMessage(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else { return "Authentication failed" }
        return message
    }
}

/// Errors thrown by RiviumChat SDK.
public enum RiviumChatError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case connectionError(Error)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .connectionError(let error):
            return "Connection error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
