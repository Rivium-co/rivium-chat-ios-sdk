import XCTest
@testable import RiviumChat

/// A clock the test drives: `sleep` records the wait and suspends until `fire()`.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [UInt64] = []
    private var pending: [CheckedContinuation<Void, Never>] = []

    func sleep(_ nanoseconds: UInt64) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            waits.append(nanoseconds)
            pending.append(c)
            lock.unlock()
        }
    }

    /// Requested waits, in seconds.
    var seconds: [Double] {
        lock.lock(); defer { lock.unlock() }
        return waits.map { Double($0) / 1_000_000_000 }
    }

    var waiting: Int { lock.lock(); defer { lock.unlock() }; return pending.count }

    func fire() {
        lock.lock()
        let c = pending.isEmpty ? nil : pending.removeFirst()
        lock.unlock()
        c?.resume()
    }

    func waitUntil(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if seconds.count >= count && waiting > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for sleep #\(count)", file: file, line: line)
    }
}

final class OutboxTimingTests: XCTestCase {

    private let sleeper = ManualSleeper()
    private let online = LockedFlag(false)
    private let events = OutboxEvents()
    private var attempts: [String] { lock.lock(); defer { lock.unlock() }; return _attempts }
    private var _attempts: [String] = []
    private let lock = NSLock()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func outbox(gate: ManualSleeper? = nil, now: @escaping () -> Date) -> Outbox {
        Outbox(
            store: MemoryOutboxStore(),
            userId: "user-42",
            sender: { [unowned self] p in
                self.lock.lock(); self._attempts.append(p.content); self.lock.unlock()
                if let gate { await gate.sleep(1) } // the request is in flight until the test lets it finish
                if !self.online.value { throw URLError(.notConnectedToInternet) }
                return Message(id: "m-\(self.attempts.count)", roomId: p.roomId, senderUserId: p.senderUserId,
                               content: p.content, createdAt: Date(), clientMessageId: p.clientMessageId)
            },
            onSent: { [events] in events.add(sent: $0) },
            onFailed: { [events] in events.add(failed: $0) },
            now: now,
            sleep: { [sleeper] in await sleeper.sleep($0) }
        )
    }

    private func item(_ content: String, room: String = "room-1") -> PendingMessage {
        PendingMessage(clientMessageId: content, roomId: room, senderUserId: "user-42", content: content, createdAt: start)
    }

    func testBackoffDoublesFrom2sToAtMost60s() async throws {
        let box = outbox(now: { self.start })
        _ = try await box.send(item("a"))
        for n in 1...7 {
            await sleeper.waitUntil(n)
            sleeper.fire()
        }
        await sleeper.waitUntil(8)
        XCTAssertEqual(Array(sleeper.seconds.prefix(8)), [2, 4, 8, 16, 32, 60, 60, 60])
        box.dispose()
    }

    func testBackoffResetsAfterASuccess() async throws {
        let box = outbox(now: { self.start })
        _ = try await box.send(item("a"))
        await sleeper.waitUntil(1)
        sleeper.fire()
        await sleeper.waitUntil(2)
        XCTAssertEqual(box.currentBackoff, 4)
        online.value = true
        await box.flush()
        XCTAssertEqual(events.sent.map(\.message.content), ["a"])
        XCTAssertEqual(box.currentBackoff, 0)
        sleeper.fire() // the old timer finds nothing left
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(attempts, ["a", "a", "a"])
        box.dispose()
    }

    func testRacingConnectEventsNeverSendAMessageTwice() async throws {
        let box = outbox(now: { self.start })
        _ = try await box.send(item("a"))
        _ = try await box.send(item("b"))
        online.value = true
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { box.onConnected(); await box.flush() }
            }
        }
        XCTAssertEqual(events.sent.map(\.message.content), ["a", "b"])
        // a failed once (offline), b queued behind it without a try; then one try each
        XCTAssertEqual(attempts, ["a", "a", "b"])
        box.dispose()
    }

    func testCancelDuringAnInFlightSendCannotRecallItAndEmitsNoMessageSent() async throws {
        let gate = ManualSleeper()
        let box = outbox(gate: gate, now: { self.start })
        online.value = false
        let sendTask = Task { try await box.send(self.item("a")) }
        await gate.waitUntil(1)
        gate.fire()
        _ = try await sendTask.value // queued
        online.value = true
        let flush = Task { await box.flush() }
        await gate.waitUntil(2) // the resend is in flight
        XCTAssertTrue(box.cancel("local_a"))
        gate.fire()
        await flush.value
        XCTAssertEqual(attempts, ["a", "a"])
        XCTAssertTrue(events.sent.isEmpty)
        XCTAssertTrue(box.pending(roomId: nil).isEmpty)
        box.dispose()
    }

    func testAMessageOlderThan24HoursIsDroppedAsExpiredNotSent() async throws {
        var clock = start
        let box = outbox(now: { clock })
        _ = try await box.send(item("old"))
        clock = start.addingTimeInterval(24 * 60 * 60 + 1)
        online.value = true
        await box.flush()
        XCTAssertEqual(attempts, ["old"])
        XCTAssertEqual(events.failed.single?.reason, "expired")
        XCTAssertTrue(box.pending(roomId: nil).isEmpty)
        box.dispose()
    }
}
