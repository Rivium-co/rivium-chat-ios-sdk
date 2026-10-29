import XCTest
import Combine
@testable import RiviumChat

/// A fake Chat API: stores messages and, like the real one, answers a repeat
/// of the same clientMessageId (same room and sender) with the first stored
/// message.
final class FakeChatServer: URLProtocol {
    private static let lock = NSLock()
    private static var _online = true
    private static var _loseNextAnswer = false
    private static var _status: Int?
    private static var _bodies: [[String: Any]] = []
    private static var _stored: [[String: Any]] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _online = true; _loseNextAnswer = false; _status = nil; _bodies = []; _stored = []
    }

    static var online: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _online }
        set { lock.lock(); _online = newValue; lock.unlock() }
    }
    /// Store the message, then lose the answer (the app sees a timeout).
    static var loseNextAnswer: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _loseNextAnswer }
        set { lock.lock(); _loseNextAnswer = newValue; lock.unlock() }
    }
    /// Answer every send with this status instead.
    static var status: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _status }
        set { lock.lock(); _status = newValue; lock.unlock() }
    }
    static var bodies: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _bodies }
    static var stored: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _stored }
    static var contents: [String] { stored.map { $0["content"] as! String } }

    static func session() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeChatServer.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    override func startLoading() {
        guard Self.online else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let parts = request.url!.pathComponents
        let roomId = parts[parts.firstIndex(of: "rooms")! + 1]
        let body = (try? JSONSerialization.jsonObject(with: bodyData())) as? [String: Any] ?? [:]

        Self.lock.lock()
        Self._bodies.append(body)
        if let status = Self._status {
            Self.lock.unlock()
            respond(status, ["message": "refused"])
            return
        }
        let cmid = body["clientMessageId"] as? String
        let sender = body["senderUserId"] as? String ?? ""
        var code = 201
        var message: [String: Any]
        if let cmid, let existing = Self._stored.first(where: {
            $0["roomId"] as? String == roomId && $0["senderUserId"] as? String == sender &&
                $0["clientMessageId"] as? String == cmid
        }) {
            code = 200
            message = existing
        } else {
            message = [
                "id": "m-\(Self._stored.count + 1)",
                "roomId": roomId,
                "senderUserId": sender,
                "content": body["content"] as? String ?? "",
                "type": body["type"] as? String ?? "text",
                "createdAt": "2026-10-29T10:00:00.000Z",
            ]
            if let cmid { message["clientMessageId"] = cmid }
            Self._stored.append(message)
        }
        let lose = Self._loseNextAnswer
        Self._loseNextAnswer = false
        Self.lock.unlock()

        if lose {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        respond(code, message)
    }

    private func respond(_ code: Int, _ json: [String: Any]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Collects outbox events.
final class OutboxEvents {
    private let lock = NSLock()
    private var _sent: [MessageSentEvent] = []
    private var _failed: [MessageFailedEvent] = []
    private var bag: Set<AnyCancellable> = []

    init(_ client: RiviumChatClient) {
        client.onMessageSent.sink { [weak self] e in self?.add(sent: e) }.store(in: &bag)
        client.onMessageFailed.sink { [weak self] e in self?.add(failed: e) }.store(in: &bag)
    }

    init() {}

    func add(sent: MessageSentEvent) { lock.lock(); _sent.append(sent); lock.unlock() }
    func add(failed: MessageFailedEvent) { lock.lock(); _failed.append(failed); lock.unlock() }
    var sent: [MessageSentEvent] { lock.lock(); defer { lock.unlock() }; return _sent }
    var failed: [MessageFailedEvent] { lock.lock(); defer { lock.unlock() }; return _failed }
}

final class OfflineOutboxTests: XCTestCase {

    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        FakeChatServer.reset()
    }

    private func client(
        queue: Bool = true,
        store: OutboxStore = MemoryOutboxStore(),
        tokenProvider: ChatTokenProvider? = nil
    ) -> RiviumChatClient {
        let config = RiviumChatConfig(
            apiKey: "rv_live_demo_app",
            userId: "user-42",
            tokenProvider: tokenProvider,
            queueOfflineMessages: queue,
            outboxStore: store
        )
        return RiviumChatClient(
            config: config,
            sessionConfiguration: FakeChatServer.session(),
            now: { [unowned self] in self.now },
            // Back-off timers never fire here: tests flush with retryPendingMessages().
            sleep: { _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) }
        )
    }

    func testOptionOffOfflineSendThrowsAndBodyHasNoClientMessageId() async throws {
        let chat = client(queue: false)
        FakeChatServer.online = false
        do {
            _ = try await chat.sendMessage("room-1", content: "Order #1001 is ready")
            XCTFail("expected the offline send to throw")
        } catch {
            XCTAssertNotNil(error as? URLError)
        }
        FakeChatServer.online = true
        let m = try await chat.sendMessage("room-1", content: "Order #1001 is ready")
        XCTAssertEqual(m.id, "m-1")
        XCTAssertNil(FakeChatServer.bodies.last?["clientMessageId"])
        XCTAssertTrue(chat.getPendingMessages().isEmpty)
        chat.dispose()
    }

    func testOptionOnOnlineSendCarriesAUUIDv4ClientMessageId() async throws {
        let chat = client()
        let m = try await chat.sendMessage("room-1", content: "hello")
        let cmid = try XCTUnwrap(FakeChatServer.bodies.single?["clientMessageId"] as? String)
        XCTAssertNotNil(cmid.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                                   options: .regularExpression))
        XCTAssertEqual(m.clientMessageId, cmid)
        XCTAssertFalse(m.isPending)
        chat.dispose()
    }

    func testOfflineSendIsQueuedReturnedAsPendingAndSentOnceOnReconnect() async throws {
        let chat = client()
        let events = OutboxEvents(chat)
        FakeChatServer.online = false

        let pending = try await chat.sendMessage("room-1", content: "Order #1001 is ready")
        XCTAssertTrue(pending.isPending)
        XCTAssertEqual(pending.id, "local_\(pending.clientMessageId!)")
        XCTAssertEqual(pending.senderUserId, "user-42")
        XCTAssertEqual(pending.createdAt, now)
        XCTAssertEqual(chat.getPendingMessages(roomId: "room-1").map(\.id), [pending.id])

        FakeChatServer.online = true
        await chat.retryPendingMessages()
        await chat.retryPendingMessages() // a second trigger sends nothing more

        XCTAssertEqual(FakeChatServer.contents, ["Order #1001 is ready"]) // the other user sees it once
        XCTAssertTrue(chat.getPendingMessages().isEmpty)
        let sent = try XCTUnwrap(events.sent.single)
        XCTAssertEqual(sent.localId, pending.id)
        XCTAssertEqual(sent.clientMessageId, pending.clientMessageId)
        XCTAssertEqual(sent.message.id, "m-1")
        XCTAssertEqual(sent.message.clientMessageId, pending.clientMessageId)
        chat.dispose()
    }

    func testASendWhoseAnswerWasLostIsStoredOnce() async throws {
        let chat = client()
        FakeChatServer.loseNextAnswer = true

        let pending = try await chat.sendMessage("room-1", content: "hello")
        XCTAssertTrue(pending.isPending)
        await chat.retryPendingMessages()

        XCTAssertEqual(FakeChatServer.stored.count, 1)
        let bodies = FakeChatServer.bodies
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0]["clientMessageId"] as? String, bodies[1]["clientMessageId"] as? String)
        chat.dispose()
    }

    func testOrderIsKeptAcrossSeveralQueuedMessagesAndRooms() async throws {
        let chat = client()
        FakeChatServer.online = false
        _ = try await chat.sendMessage("room-1", content: "a1")
        _ = try await chat.sendMessage("room-2", content: "b1")
        _ = try await chat.sendMessage("room-1", content: "a2")
        FakeChatServer.online = true
        // Online again, but room-1 still has older messages: this one waits behind them.
        let behind = try await chat.sendMessage("room-1", content: "a3")
        XCTAssertTrue(behind.isPending)

        await chat.retryPendingMessages()

        XCTAssertEqual(FakeChatServer.contents, ["a1", "b1", "a2", "a3"])
        chat.dispose()
    }

    func testPermanentErrorsAreNotQueuedAndThrowAsBefore() async throws {
        let chat = client()
        for code in [400, 401, 403, 404, 413] {
            FakeChatServer.status = code
            do {
                _ = try await chat.sendMessage("room-1", content: "hello")
                XCTFail("expected \(code) to throw")
            } catch RiviumChatError.httpError(let statusCode, _) {
                XCTAssertEqual(statusCode, code)
            }
        }
        XCTAssertTrue(chat.getPendingMessages().isEmpty)
        chat.dispose()
    }

    func testServerBusyTimeoutAndRateLimitAreQueued() async throws {
        let chat = client()
        FakeChatServer.status = 503
        let a = try await chat.sendMessage("room-1", content: "a")
        FakeChatServer.status = 429
        let b = try await chat.sendMessage("room-2", content: "b")
        FakeChatServer.status = 408
        let c = try await chat.sendMessage("room-3", content: "c")
        XCTAssertTrue(a.isPending && b.isPending && c.isPending)
        XCTAssertEqual(chat.getPendingMessages().count, 3)
        chat.dispose()
    }

    func testAFailingTokenProviderIsTransient() async throws {
        let failing = LockedFlag(true)
        let chat = client(tokenProvider: {
            if failing.value { throw NSError(domain: "demo_app", code: 1) }
            return "token"
        })
        let pending = try await chat.sendMessage("room-1", content: "hello")
        XCTAssertTrue(pending.isPending)
        XCTAssertTrue(FakeChatServer.bodies.isEmpty)
        failing.value = false
        await chat.retryPendingMessages()
        XCTAssertEqual(FakeChatServer.contents, ["hello"])
        chat.dispose()
    }

    func testAQueuedMessageTheServerThenRefusesFailsWithReasonRejected() async throws {
        let chat = client()
        let events = OutboxEvents(chat)
        FakeChatServer.online = false
        let pending = try await chat.sendMessage("room-1", content: "hello")
        FakeChatServer.online = true
        FakeChatServer.status = 403
        await chat.retryPendingMessages()

        let failed = try XCTUnwrap(events.failed.single)
        XCTAssertEqual(failed.localId, pending.id)
        XCTAssertEqual(failed.roomId, "room-1")
        XCTAssertEqual(failed.reason, "rejected")
        XCTAssertTrue(chat.getPendingMessages().isEmpty)
        chat.dispose()
    }

    func testExpiredMessageFailsWithReasonExpiredAndCancelRemovesOne() async throws {
        let chat = client()
        let events = OutboxEvents(chat)
        FakeChatServer.online = false
        let old = try await chat.sendMessage("room-1", content: "old")
        let other = try await chat.sendMessage("room-2", content: "cancel me")
        now = now.addingTimeInterval(24 * 60 * 60 + 1)

        XCTAssertTrue(chat.cancelPendingMessage(other.id))
        XCTAssertFalse(chat.cancelPendingMessage(other.id))
        FakeChatServer.online = true
        await chat.retryPendingMessages()

        let failed = try XCTUnwrap(events.failed.single)
        XCTAssertEqual(failed.localId, old.id)
        XCTAssertEqual(failed.reason, MessageFailedEvent.reasonExpired)
        XCTAssertTrue(FakeChatServer.stored.isEmpty)
        XCTAssertTrue(events.sent.isEmpty) // cancel emits nothing
        chat.dispose()
    }

    func testTheStoreKeepsTheQueueForTheNextClientAndClearEmptiesIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileOutboxStore(directory: dir, name: FileOutboxStore.name(apiKey: "rv_live_demo_app", userId: "user-42"))

        let first = client(store: store)
        FakeChatServer.online = false
        let pending = try await first.sendMessage("room-1", content: "survives a restart", metadata: ["orderId": "1001", "count": 2])
        first.dispose()
        XCTAssertEqual(FileOutboxStore(directory: dir, name: FileOutboxStore.name(apiKey: "rv_live_demo_app", userId: "user-42")).load().count, 1)

        FakeChatServer.online = true
        let second = client(store: FileOutboxStore(directory: dir, name: FileOutboxStore.name(apiKey: "rv_live_demo_app", userId: "user-42")))
        let restored = second.getPendingMessages()
        XCTAssertEqual(restored.map(\.id), [pending.id])
        XCTAssertEqual(restored.first?.createdAt, now)
        await second.retryPendingMessages()
        XCTAssertEqual(FakeChatServer.contents, ["survives a restart"])
        let body = try XCTUnwrap(FakeChatServer.bodies.last)
        XCTAssertEqual(body["clientMessageId"] as? String, pending.clientMessageId)
        let metadata = try XCTUnwrap(body["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["orderId"] as? String, "1001")
        XCTAssertEqual(metadata["count"] as? Int, 2)

        FakeChatServer.online = false
        _ = try await second.sendMessage("room-1", content: "x")
        second.clearPendingMessages()
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertTrue(second.getPendingMessages().isEmpty)
        second.dispose()
    }

    func testStoredItemsOfAnotherSenderAreDroppedNeverSent() async throws {
        let store = MemoryOutboxStore()
        store.save([
            PendingMessage(clientMessageId: "x", roomId: "room-1", senderUserId: "user-7", content: "from another user", createdAt: now),
            PendingMessage(clientMessageId: "y", roomId: "room-1", senderUserId: "user-42", content: "mine", createdAt: now),
        ])
        let chat = client(store: store)
        XCTAssertEqual(chat.getPendingMessages().map(\.id), ["local_y"])
        await chat.retryPendingMessages()
        XCTAssertEqual(FakeChatServer.contents, ["mine"])
        chat.dispose()
    }

    func testRacingReconnectTriggersSendEachMessageOnce() async throws {
        let chat = client()
        FakeChatServer.online = false
        for i in 0..<5 { _ = try await chat.sendMessage("room-1", content: "m\(i)") }
        FakeChatServer.online = true

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await chat.retryPendingMessages() } }
        }

        XCTAssertEqual(FakeChatServer.contents, ["m0", "m1", "m2", "m3", "m4"])
        XCTAssertEqual(FakeChatServer.bodies.count, 5) // offline tries never reach the server
        chat.dispose()
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

extension Array {
    /// The only element, or nil when there is not exactly one.
    var single: Element? { count == 1 ? first : nil }
}
