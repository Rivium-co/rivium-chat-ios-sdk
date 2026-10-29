import Foundation

/// A JSON value, so a queued message's metadata can be stored.
public enum OutboxJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([OutboxJSONValue])
    case object([String: OutboxJSONValue])
    case null

    init(any value: Any) {
        if let v = value as? Bool, type(of: value) == Bool.self {
            self = .bool(v)
        } else if let v = value as? String {
            self = .string(v)
        } else if let n = value as? NSNumber {
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        } else if let v = value as? [Any] {
            self = .array(v.map { OutboxJSONValue(any: $0) })
        } else if let v = value as? [String: Any] {
            self = .object(v.mapValues { OutboxJSONValue(any: $0) })
        } else {
            self = .null
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v && abs(v) < 9e15 ? Int(v) as Any : v
        case .bool(let v): return v
        case .array(let v): return v.map(\.anyValue)
        case .object(let v): return v.mapValues(\.anyValue)
        case .null: return NSNull()
        }
    }

    /// Text for ``Message/metadata`` (`[String: String]`).
    var text: String {
        switch self {
        case .string(let v): return v
        case .number, .bool: return "\(anyValue)"
        case .null: return ""
        case .array, .object:
            let data = (try? JSONSerialization.data(withJSONObject: anyValue)) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([OutboxJSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: OutboxJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// A message written while offline that waits in the outbox
/// (only with ``RiviumChatConfig/queueOfflineMessages``).
///
/// ``localId`` is `local_<clientMessageId>`, the id of the pending
/// ``Message`` that `sendMessage` returned.
public struct PendingMessage: Codable, Equatable {
    /// Prefix of a pending message's id.
    public static let localIdPrefix = "local_"

    public let localId: String
    public let clientMessageId: String
    public let roomId: String
    public let senderUserId: String
    public let content: String
    public let type: MessageType
    public let attachments: [Attachment]?
    public let metadataValues: [String: OutboxJSONValue]?
    public let replyToId: String?
    /// When the message was written.
    public let createdAt: Date

    public init(
        clientMessageId: String,
        roomId: String,
        senderUserId: String,
        content: String,
        type: MessageType = .text,
        attachments: [Attachment]? = nil,
        metadata: [String: Any]? = nil,
        replyToId: String? = nil,
        createdAt: Date
    ) {
        self.localId = Self.localIdPrefix + clientMessageId
        self.clientMessageId = clientMessageId
        self.roomId = roomId
        self.senderUserId = senderUserId
        self.content = content
        self.type = type
        self.attachments = attachments
        self.metadataValues = metadata?.mapValues { OutboxJSONValue(any: $0) }
        self.replyToId = replyToId
        self.createdAt = createdAt
    }

    /// The metadata as passed to `sendMessage`.
    public var metadata: [String: Any]? {
        metadataValues?.mapValues(\.anyValue)
    }

    /// The pending message as the app shows it: `isPending = true`.
    public func toMessage() -> Message {
        Message(
            id: localId,
            roomId: roomId,
            senderUserId: senderUserId,
            content: content,
            type: type,
            attachments: attachments,
            metadata: metadataValues?.mapValues(\.text),
            replyToId: replyToId,
            createdAt: createdAt,
            isPending: true,
            clientMessageId: clientMessageId
        )
    }
}
