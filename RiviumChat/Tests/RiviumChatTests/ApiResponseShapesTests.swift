import XCTest
@testable import RiviumChat
import SwiftCentrifuge

/// Answers every request with `body` and keeps what was sent.
private final class StubProtocol: URLProtocol {
    static var body = Data("[]".utf8)
    static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(body: String) {
        lock.lock(); defer { lock.unlock() }
        self.body = Data(body.utf8)
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Requests and responses as the Chat API sends them.
final class ApiResponseShapesTests: XCTestCase {

    private func message(_ id: String, _ content: String = "hello") -> String {
        """
        {"id":"\(id)","roomId":"room-1","senderUserId":"bob","content":"\(content)",
         "type":"text","isDeleted":false,"createdAt":"2026-10-29T10:00:00Z"}
        """
    }

    private func api(_ body: String, tokenProvider: ChatTokenProvider? = nil) -> ApiService {
        StubProtocol.reset(body: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let config = RiviumChatConfig(apiKey: "rv_live_test", userId: "alice", tokenProvider: tokenProvider)
        return ApiService(config: config, sessionConfiguration: configuration)
    }

    func testSearchReadsTheMessagesOfTheMessagesAndTotalObject() async throws {
        let body = #"{"messages":[\#(message("m-1")),\#(message("m-2"))],"total":7}"#

        let results = try await api(body).searchMessages("room-1", userId: "alice", query: "hello")

        XCTAssertEqual(results.map(\.id), ["m-1", "m-2"])
    }

    func testSearchMessagesWithTotalReportsTheTotalNumberOfMatches() async throws {
        let body = #"{"messages":[\#(message("m-1")),\#(message("m-2"))],"total":5}"#

        let result = try await api(body).searchMessagesWithTotal("room-1", userId: "alice", query: "hello", limit: 2)

        XCTAssertEqual(result.messages.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(result.total, 5)
        XCTAssertTrue(result.hasMore)
    }

    func testSearchMessagesWithTotalLastPageHasNoMore() async throws {
        let body = #"{"messages":[\#(message("m-3"))],"total":3}"#

        let result = try await api(body).searchMessagesWithTotal("room-1", userId: "alice", query: "hello", limit: 2, offset: 2)

        XCTAssertEqual(result.total, 3)
        XCTAssertFalse(result.hasMore)
    }

    func testSearchMessagesWithTotalAcceptsABareArray() async throws {
        let result = try await api("[\(message("m-1"))]").searchMessagesWithTotal("room-1", userId: "alice", query: "hello")

        XCTAssertEqual(result.total, 1)
        XCTAssertFalse(result.hasMore)
    }

    func testSearchTextIsEncodedInTheURL() async throws {
        _ = try await api(#"{"messages":[],"total":0}"#)
            .searchMessages("room-1", userId: "alice", query: "Order #1001 & co")

        let url = try XCTUnwrap(StubProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "Order #1001 & co")
        XCTAssertEqual(items.first { $0.name == "userId" }?.value, "alice")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
        XCTAssertNil(url.fragment)
    }

    func testMentionsReturnTheMentioningMessagesOfTheMentionRecords() async throws {
        let body = """
        [{"id":"men-1","messageId":"m-1","mentionedUserId":"alice","roomId":"room-1",
          "createdAt":"2026-10-29T10:00:01Z","message":\(message("m-1", "hi @alice"))},
         {"id":"men-2","messageId":"m-2","mentionedUserId":"alice","roomId":"room-1",
          "createdAt":"2026-10-29T10:00:02Z","message":null}]
        """

        let mentions = try await api(body).getMentions("room-1", userId: "alice")

        XCTAssertEqual(mentions.map(\.id), ["m-1"])
        XCTAssertEqual(mentions.first?.content, "hi @alice")
        XCTAssertEqual(mentions.first?.senderUserId, "bob")
    }

    func testAFailingTokenProviderOnTheRealtimePathReportsTokenProviderFailed() async {
        struct Offline: Error {}
        let service = api("[]", tokenProvider: { throw Offline() })
        var events: [AuthErrorEvent] = []
        service.onAuthError = { events.append($0) }

        do {
            _ = try await service.userTokenOrNil()
            XCTFail("expected the provider error")
        } catch {
            XCTAssertTrue(error is Offline)
        }

        XCTAssertEqual(events.map(\.code), ["token_provider_failed"])
    }
}

final class RealtimeServiceTests: XCTestCase {
    private let config = RiviumChatConfig(apiKey: "rv_live_test", userId: "alice")

    private func ask(_ service: RealtimeService) async -> Result<String, Error> {
        await withCheckedContinuation { continuation in
            service.connectionTokenGetter()(CentrifugeConnectionTokenEvent()) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func testTokenGetterFetchesAFreshTokenFromTheSameSourceEveryTime() async throws {
        let counter = Counter()
        let service = RealtimeService(config) { "token-\(await counter.next())" }

        let first = try await ask(service).get()
        let second = try await ask(service).get()

        XCTAssertEqual(first, "token-1")
        XCTAssertEqual(second, "token-2")
    }

    func testTokenGetterHandsAFailureBackToCentrifuge() async {
        struct Offline: Error {}
        let service = RealtimeService(config) { throw Offline() }

        guard case .failure(let error) = await ask(service) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(error is Offline)
    }

    func testTypingIsThrottledPerRoomNotPerClient() {
        let service = RealtimeService(config) { "t" }

        XCTAssertTrue(service.shouldPublishTyping("room-a", now: 10))
        // Another room right away is not muted by room-a.
        XCTAssertTrue(service.shouldPublishTyping("room-b", now: 10.1))
        // The same room inside two seconds is.
        XCTAssertFalse(service.shouldPublishTyping("room-a", now: 11))
        XCTAssertTrue(service.shouldPublishTyping("room-a", now: 12))
    }
}

final class DisposedClientTests: XCTestCase {
    func testCallsAfterDisposeThrowInsteadOfCrashing() async {
        let client = RiviumChatClient(config: RiviumChatConfig(apiKey: "rv_live_test", userId: "alice"))
        client.dispose()

        do {
            _ = try await client.listRooms()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is RiviumChatClientDisposedError)
            XCTAssertEqual(error.localizedDescription, "RiviumChatClient has been disposed")
        }

        // Calls that cannot throw do nothing.
        client.subscribeRoom("room-1")
        client.publishTyping("room-1")
        client.disconnect()
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}
