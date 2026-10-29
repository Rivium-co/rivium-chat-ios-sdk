import Foundation

/// Where the outbox keeps messages written while offline.
///
/// The default (``MemoryOutboxStore``) survives a lost network, not an app
/// restart. ``FileOutboxStore`` keeps them across restarts; pass your own
/// implementation for any other storage. Calls may come from any thread.
public protocol OutboxStore: AnyObject {
    /// Returns the saved messages in the order they were written.
    func load() -> [PendingMessage]
    /// Replaces the saved messages with `items`.
    func save(_ items: [PendingMessage])
}

/// Keeps the outbox in memory only (the default).
public final class MemoryOutboxStore: OutboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [PendingMessage] = []

    public init() {}

    public func load() -> [PendingMessage] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func save(_ items: [PendingMessage]) {
        lock.lock(); defer { lock.unlock() }
        self.items = items
    }
}

/// Keeps the outbox in a JSON file (by default in Application Support), so
/// messages written offline are still sent after an app restart.
public final class FileOutboxStore: OutboxStore, @unchecked Sendable {
    private let lock = NSLock()
    /// The file the queue is written to.
    public let fileURL: URL

    /// - Parameters:
    ///   - directory: where the file goes; default `Application Support/RiviumChat`.
    ///   - name: one name per project and user; ``name(apiKey:userId:)`` builds one.
    public init(directory: URL? = nil, name: String) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("RiviumChat", isDirectory: true)
        let safe = name.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_" }
            .joined()
        self.fileURL = base.appendingPathComponent("\(safe).json")
    }

    /// A file name for one project (`apiKey`) and one user (`userId`).
    public static func name(apiKey: String, userId: String) -> String {
        // FNV-1a, 64 bit: a stable, file-safe name.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(apiKey)\u{0}\(userId)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "outbox_" + String(hash, radix: 16)
    }

    public func load() -> [PendingMessage] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([PendingMessage].self, from: data)) ?? []
    }

    public func save(_ items: [PendingMessage]) {
        lock.lock(); defer { lock.unlock() }
        do {
            if items.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            // Best effort: the outbox keeps working in memory.
        }
    }
}
