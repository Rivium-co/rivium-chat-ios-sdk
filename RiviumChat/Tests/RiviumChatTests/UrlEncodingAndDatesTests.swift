import XCTest
@testable import RiviumChat

/// Answers every request with `body` and keeps what was sent.
private final class RouteStub: URLProtocol {
    static var body = Data("[]".utf8)
    static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(body: String) {
        lock.lock(); defer { lock.unlock() }
        self.body = Data(body.utf8)
        requests = []
    }

    static var last: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Every caller-supplied value in a URL reaches the server exactly as given.
final class UrlEncodingTests: XCTestCase {

    private let message = #"{"id":"m-1","roomId":"r","senderUserId":"bob","content":"x","type":"text","createdAt":"2026-10-29T10:00:00Z"}"#
    private let room = #"{"id":"r","type":"direct","participants":[]}"#

    // Values with every character that changes a URL's meaning, plus non-ASCII.
    private let roomId = "room/1?x=#a b%2Fé"
    private let messageId = "msg/1?#;"
    private let userId = "user+1&admin=true#x y/é"

    private func api(_ body: String) -> ApiService {
        RouteStub.reset(body: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RouteStub.self]
        return ApiService(
            config: RiviumChatConfig(apiKey: "rv_live_test", userId: "alice"),
            sessionConfiguration: configuration
        )
    }

    private func lastComponents(file: StaticString = #filePath, line: UInt = #line) throws -> URLComponents {
        let url = try XCTUnwrap(RouteStub.last?.url, file: file, line: line)
        return try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false), file: file, line: line)
    }

    /// The decoded path segments, split on the real "/" separators only.
    private func assertPath(_ segments: String..., file: StaticString = #filePath, line: UInt = #line) throws {
        let components = try lastComponents(file: file, line: line)
        let decoded = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? "?" }
        XCTAssertEqual(decoded, ["api", "v1"] + segments, file: file, line: line)
        XCTAssertNil(components.fragment, file: file, line: line)
    }

    private func query(_ name: String) throws -> String? {
        try lastComponents().queryItems?.first { $0.name == name }?.value
    }

    func testRoomRoutesEncodeTheRoomIdAsOneSegment() async throws {
        _ = try await api(room).getRoom(roomId)
        try assertPath("rooms", roomId)
        XCTAssertNil(try lastComponents().percentEncodedQuery)

        _ = try await api(#"{"id":"p","externalUserId":"u","role":"member","joinedAt":"2026-10-29T10:00:00Z"}"#)
            .addParticipant(roomId, externalUserId: userId)
        try assertPath("rooms", roomId, "participants")

        _ = try await api(message).sendMessage(roomId, senderUserId: userId, content: "hi")
        try assertPath("rooms", roomId, "messages")

        try await api("{}").markAsRead(roomId, userId)
        try assertPath("rooms", roomId, "read")

        _ = try await api("[]").getPinnedMessages(roomId)
        try assertPath("rooms", roomId, "pinned")

        _ = try await api(room).getRoomByExternalId("Order #1001/a&b?")
        try assertPath("rooms", "by-external-id", "Order #1001/a&b?")
    }

    func testQueryValuesAreEncodedPlusSignsIncluded() async throws {
        _ = try await api("[]").listRooms(userId)
        try assertPath("rooms")
        XCTAssertEqual(try query("userId"), userId)
        XCTAssertEqual(try lastComponents().queryItems?.map(\.name), ["userId"])
        XCTAssertFalse(try lastComponents().percentEncodedQuery!.contains("+"))

        _ = try await api(#"{"messages":[],"hasMore":false}"#)
            .getMessages(roomId, userId: userId, limit: 10, before: "2026-10-29T10:00:00.123+04:00")
        try assertPath("rooms", roomId, "messages")
        XCTAssertEqual(try query("userId"), userId)
        XCTAssertEqual(try query("limit"), "10")
        XCTAssertEqual(try query("before"), "2026-10-29T10:00:00.123+04:00")

        _ = try await api(#"{"totalUnread":0,"rooms":[]}"#).getUnreadSummary(userId)
        try assertPath("rooms", "unread-summary")
        XCTAssertEqual(try query("userId"), userId)

        _ = try await api("[]").getMentions(roomId, userId: userId, limit: 5, offset: 2)
        try assertPath("rooms", roomId, "mentions")
        XCTAssertEqual(try query("userId"), userId)
        XCTAssertEqual(try query("limit"), "5")
        XCTAssertEqual(try query("offset"), "2")

        _ = try await api(#"{"messages":[]}"#).searchMessages(roomId, userId: userId, query: "a+b & c é")
        try assertPath("rooms", roomId, "messages", "search")
        XCTAssertEqual(try query("q"), "a+b & c é")
        XCTAssertEqual(try query("userId"), userId)
    }

    func testMessageRoutesEncodeTheMessageIdAsOneSegment() async throws {
        try await api("{}").deleteMessage(messageId, userId)
        try assertPath("messages", messageId)
        XCTAssertEqual(try query("userId"), userId)

        _ = try await api(message).editMessage(messageId, userId: userId, content: "new")
        try assertPath("messages", messageId)

        let reaction = #"{"id":"x","messageId":"m","userId":"u","emoji":"+1","createdAt":"2026-10-29T10:00:00Z"}"#
        _ = try await api(reaction).addReaction(messageId, userId: userId, emoji: "+1")
        try assertPath("messages", messageId, "reactions")

        try await api("{}").removeReaction(messageId, userId: userId, emoji: "+1")
        try assertPath("messages", messageId, "reactions")

        _ = try await api("[]").getReactions(messageId)
        try assertPath("messages", messageId, "reactions")

        _ = try await api(message).pinMessage(messageId, userId: userId)
        try assertPath("messages", messageId, "pin")

        try await api("{}").unpinMessage(messageId, userId: userId)
        try assertPath("messages", messageId, "pin")
    }

    func testAnIdThatWouldChangeTheRouteIsRefused() async {
        for bad in ["", ".", ".."] {
            do {
                _ = try await api(room).getRoom(bad)
                XCTFail("getRoom(\"\(bad)\") should fail")
            } catch {
                guard case RiviumChatError.invalidURL = error else {
                    return XCTFail("unexpected error \(error)")
                }
            }
        }
        XCTAssertTrue(RouteStub.requests.isEmpty)
    }
}

/// Server dates carry milliseconds ("2026-10-29T10:00:00.123Z"); older ones may not.
final class DateDecodingTests: XCTestCase {

    private struct Stamp: Decodable { let at: Date }

    private func decode(_ text: String) throws -> Date {
        try RiviumChatJSON.decoder().decode(Stamp.self, from: Data(#"{"at":"\#(text)"}"#.utf8)).at
    }

    /// Why: before iOS 26, `.iso8601` used this formatter, which refuses milliseconds.
    func testTheDefaultISO8601FormatterRefusesMilliseconds() {
        XCTAssertNil(ISO8601DateFormatter().date(from: "2026-10-29T10:00:00.123Z"))
    }

    func testDatesWithMillisecondsDecode() throws {
        let date = try decode("2026-10-29T10:00:00.123Z")
        XCTAssertEqual(date.timeIntervalSince1970, 1_793_268_000.123, accuracy: 0.0005)
    }

    func testDatesWithoutFractionalSecondsDecode() throws {
        XCTAssertEqual(try decode("2026-10-29T10:00:00Z").timeIntervalSince1970, 1_793_268_000)
    }

    func testDatesWithAnOffsetDecode() throws {
        XCTAssertEqual(try decode("2026-10-29T14:00:00.500+04:00").timeIntervalSince1970, 1_793_268_000.5, accuracy: 0.0005)
    }

    func testAnInvalidDateIsADecodingError() {
        XCTAssertThrowsError(try decode("yesterday")) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testAMessageFromTheServerDecodes() throws {
        let body = #"""
        {"id":"m-1","roomId":"room-1","senderUserId":"bob","content":"hi","type":"text",
         "isDeleted":false,"createdAt":"2026-10-29T10:00:00.123Z","isEdited":true,
         "editedAt":"2026-10-29T10:01:00.456Z","isPinned":false,"pinnedAt":null}
        """#
        let message = try RiviumChatJSON.decoder().decode(Message.self, from: Data(body.utf8))
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, 1_793_268_000.123, accuracy: 0.0005)
        XCTAssertEqual(message.editedAt?.timeIntervalSince1970 ?? 0, 1_793_268_060.456, accuracy: 0.0005)
        XCTAssertNil(message.pinnedAt)
    }
}
