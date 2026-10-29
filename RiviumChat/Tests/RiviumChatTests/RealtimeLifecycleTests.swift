import XCTest
import Combine
import SwiftCentrifuge
@testable import RiviumChat

/// Connection and subscription outcomes the app must hear about.
final class RealtimeLifecycleTests: XCTestCase {

    private let config = RiviumChatConfig(apiKey: "rv_live_test", userId: "user-42")
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private struct TokenFailure: Error {}

    func testAFailingConnectionTokenSetsTheErrorStateAndReportsIt() async {
        let service = RealtimeService(config) { throw TokenFailure() }
        let reported = expectation(description: "onConnectionError")
        service.onConnectionError.sink { _ in reported.fulfill() }.store(in: &cancellables)

        do {
            try await service.connect()
            XCTFail("connect() must throw when the token cannot be fetched")
        } catch {}

        await fulfillment(of: [reported], timeout: 2)
        XCTAssertEqual(service.currentConnectionState, .error)
        XCTAssertFalse(service.hasClient)
    }

    func testDisconnectWhileTheTokenIsFetchedOpensNoConnection() async {
        let service = RealtimeService(config) {
            try await Task.sleep(nanoseconds: 300_000_000)
            return "token"
        }

        let connecting = Task { try? await service.connect() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        service.disconnect()

        let finished = expectation(description: "connect() returns")
        Task {
            _ = await connecting.value
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)

        XCTAssertFalse(service.hasClient, "a socket was opened after disconnect()")
        XCTAssertEqual(service.currentConnectionState, .disconnected)
    }

    func testARoomTheServerRefusesIsReportedWithItsCodeAndReason() async {
        let service = RealtimeService(config) { "token" }
        let refused = expectation(description: "recoveryFailed")
        let state = expectation(description: "unsubscribed with code")
        var event: SubscriptionStateEvent?
        service.onRecoveryFailed.sink { roomId in
            XCTAssertEqual(roomId, "room-1")
            refused.fulfill()
        }.store(in: &cancellables)
        service.onSubscriptionState.sink {
            event = $0
            state.fulfill()
        }.store(in: &cancellables)

        // The realtime client ends a subscription the server refuses for good with the
        // server's code and reason (no error callback).
        service.handleUnsubscribed(roomId: "room-1", channel: "chat:room_room-1", code: 403, reason: "Not a participant in this room")

        await fulfillment(of: [refused, state], timeout: 2)
        XCTAssertEqual(event?.status, .unsubscribed)
        XCTAssertEqual(event?.code, 403)
        XCTAssertEqual(event?.reason, "Not a participant in this room")
    }

    func testRefusedPresenceAndTypingCarryTheirCodeToo() async {
        let service = RealtimeService(config) { "token" }
        let state = expectation(description: "unsubscribed with code")
        var event: SubscriptionStateEvent?
        service.onSubscriptionState.sink {
            event = $0
            state.fulfill()
        }.store(in: &cancellables)

        service.handleUnsubscribed(roomId: "room-1", channel: "typing:room_room-1", code: 403, reason: "Not a participant in this room")

        await fulfillment(of: [state], timeout: 2)
        XCTAssertEqual(event?.code, 403)
        XCTAssertEqual(event?.reason, "Not a participant in this room")
    }

    func testUnsubscribingMyselfIsNotARefusal() async {
        let service = RealtimeService(config) { "token" }
        let refused = expectation(description: "no recoveryFailed")
        refused.isInverted = true
        service.onRecoveryFailed.sink { _ in refused.fulfill() }.store(in: &cancellables)

        service.handleUnsubscribed(roomId: "room-1", channel: "chat:room_room-1", code: 0, reason: "unsubscribe called")

        await fulfillment(of: [refused], timeout: 0.3)
    }

    func testASubscribeErrorCarriesTheServersCode() {
        let failure = RealtimeService.subscriptionFailure(
            RealtimeErrorForTests.subscribe(code: 403, message: "Not a participant in this room")
        )
        XCTAssertEqual(failure.code, 403)
        XCTAssertEqual(failure.reason, "Not a participant in this room")
    }
}

enum RealtimeErrorForTests {
    static func subscribe(code: UInt32, message: String) -> Error {
        CentrifugeError.subscriptionSubscribeError(
            error: CentrifugeError.replyError(code: code, message: message, temporary: false)
        )
    }
}
