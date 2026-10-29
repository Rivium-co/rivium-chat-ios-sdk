import Foundation

/// Keeps messages written without network and sends them when the
/// connection is back: one at a time, in the order written, never twice
/// (every message carries its clientMessageId, so a resend whose first
/// answer was lost is stored once by the server).
///
/// State is guarded by a lock; flushes run one after the other (a chain of
/// tasks), so racing connect events never send a message twice.
final class Outbox: @unchecked Sendable {
    typealias Sender = (PendingMessage) async throws -> Message
    /// Waits the given nanoseconds; tests pass a manual clock.
    typealias Sleep = (UInt64) async throws -> Void

    static let initialBackoff: TimeInterval = 2
    static let maxBackoff: TimeInterval = 60
    static let maxAge: TimeInterval = 24 * 60 * 60

    private let store: OutboxStore
    private let userId: String
    private let sender: Sender
    private let now: () -> Date
    private let sleep: Sleep
    private let onSent: (MessageSentEvent) -> Void
    private let onFailed: (MessageFailedEvent) -> Void

    private let lock = NSLock()
    private var loaded: [PendingMessage]?
    private var flushChain: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var backoff: TimeInterval = 0
    private var disposed = false

    init(
        store: OutboxStore,
        userId: String,
        sender: @escaping Sender,
        onSent: @escaping (MessageSentEvent) -> Void,
        onFailed: @escaping (MessageFailedEvent) -> Void,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.store = store
        self.userId = userId
        self.sender = sender
        self.onSent = onSent
        self.onFailed = onFailed
        self.now = now
        self.sleep = sleep
    }

    /// Runs `body` under the lock (a plain function, so async code can call it).
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// The current back-off (0 = none since the last success).
    var currentBackoff: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return backoff
    }

    // MARK: - Queue (callers hold no lock)

    private func withItems<T>(_ body: (inout [PendingMessage]) -> T) -> (T, [PendingMessage]) {
        lock.lock(); defer { lock.unlock() }
        // Items another user wrote on this device are never sent.
        var items = loaded ?? store.load().filter { $0.senderUserId == userId }
        let result = body(&items)
        loaded = items
        return (result, items)
    }

    private func enqueue(_ item: PendingMessage) {
        let (_, snapshot) = withItems { $0.append(item) }
        store.save(snapshot)
    }

    @discardableResult
    private func remove(_ localId: String) -> Bool {
        let (removed, snapshot) = withItems { items -> Bool in
            let before = items.count
            items.removeAll { $0.localId == localId }
            return items.count != before
        }
        if removed { store.save(snapshot) }
        return removed
    }

    func pending(roomId: String?) -> [PendingMessage] {
        withItems { _ in () }.1.filter { roomId == nil || $0.roomId == roomId }
    }

    func cancel(_ localId: String) -> Bool { remove(localId) }

    func clear() {
        lock.lock()
        loaded = []
        lock.unlock()
        store.save([])
    }

    /// Forgets everything in memory; a persistent store keeps its copy.
    func dispose() {
        lock.lock()
        disposed = true
        loaded = []
        retryTask?.cancel()
        retryTask = nil
        lock.unlock()
    }

    private var isDisposed: Bool {
        lock.lock(); defer { lock.unlock() }
        return disposed
    }

    // MARK: - Sending

    /// Sends `item` now, or queues it when the failure is transient (or when
    /// older messages of the same room still wait, so the order is kept).
    /// Permanent failures are thrown.
    func send(_ item: PendingMessage) async throws -> Message {
        if !pending(roomId: item.roomId).isEmpty {
            enqueue(item)
            Task { await self.flush() }
            return item.toMessage()
        }
        do {
            return try await sender(item)
        } catch {
            guard Self.isTransient(error) else { throw error }
            enqueue(item)
            scheduleRetry()
            return item.toMessage()
        }
    }

    /// The realtime connection is up: send what waits.
    func onConnected() {
        guard !isDisposed else { return }
        Task { await self.flush() }
    }

    /// Sends what waits and returns when done (or stopped by a transient failure).
    func flush() async {
        let task: Task<Void, Never>? = locked {
            if disposed { return nil }
            let previous = flushChain
            let task = Task { [weak self] in
                await previous?.value
                await self?.flushOnce()
            }
            flushChain = task
            return task
        }
        await task?.value
    }

    private func flushOnce() async {
        while !isDisposed {
            guard let next = pending(roomId: nil).first else { return }

            if now().timeIntervalSince(next.createdAt) > Self.maxAge {
                if remove(next.localId) {
                    onFailed(MessageFailedEvent(
                        localId: next.localId,
                        clientMessageId: next.clientMessageId,
                        roomId: next.roomId,
                        error: "The message waited more than 24 hours without network",
                        reason: MessageFailedEvent.reasonExpired
                    ))
                }
                continue
            }

            do {
                let message = try await sender(next)
                locked { backoff = 0 }
                // Cancelled while it was being sent: stored anyway, but no messageSent.
                if remove(next.localId) {
                    onSent(MessageSentEvent(localId: next.localId, clientMessageId: next.clientMessageId, message: message))
                }
            } catch {
                if Self.isTransient(error) {
                    scheduleRetry()
                    return
                }
                if remove(next.localId) {
                    onFailed(MessageFailedEvent(
                        localId: next.localId,
                        clientMessageId: next.clientMessageId,
                        roomId: next.roomId,
                        error: error.localizedDescription,
                        reason: MessageFailedEvent.reasonRejected
                    ))
                }
            }
        }
    }

    private func scheduleRetry() {
        lock.lock()
        defer { lock.unlock() }
        guard !disposed else { return }
        backoff = backoff == 0 ? Self.initialBackoff : min(backoff * 2, Self.maxBackoff)
        let wait = backoff
        retryTask?.cancel()
        let sleep = self.sleep
        retryTask = Task { [weak self] in
            try? await sleep(UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.locked { self.retryTask = nil }
            await self.flush()
        }
    }

    // MARK: - Errors

    private static let transientURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        .callIsActive, .secureConnectionFailed, .backgroundSessionWasDisconnected,
    ]

    /// Transient: no answer (no network, timeout, connection lost, a failing
    /// tokenProvider), a 5xx, 408 or 429. Every other 4xx (400, 401, 403, 404,
    /// 413 …) is permanent.
    static func isTransient(_ error: Error) -> Bool {
        if error is TokenProviderFailure { return true }
        if let error = error as? RiviumChatError {
            switch error {
            case .httpError(let statusCode, _):
                return statusCode >= 500 || statusCode == 408 || statusCode == 429
            case .connectionError(let inner):
                return isTransient(inner)
            default:
                return false
            }
        }
        if let error = error as? URLError {
            return transientURLCodes.contains(error.code)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return transientURLCodes.contains(URLError.Code(rawValue: ns.code))
        }
        return false
    }
}
