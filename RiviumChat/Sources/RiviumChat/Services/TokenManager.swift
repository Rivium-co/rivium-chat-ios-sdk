import Foundation

/// Holds the current user token and refreshes it through the app's
/// ``ChatTokenProvider``.
///
/// - Reuses the cached token until shortly before it expires, then fetches a
///   new one before the request, so an expired token rarely reaches the server.
/// - An actor, so concurrent callers share one in-flight refresh: a burst of
///   requests triggers a single call to your server.
actor TokenManager {
    /// Refresh this long before `exp`, to absorb clock skew and request time.
    static let refreshMargin: TimeInterval = 60

    private let provider: ChatTokenProvider
    private let now: () -> Date
    private var token: String?
    private var expiresAt: Date?
    private var inFlight: Task<String, Error>?

    init(provider: @escaping ChatTokenProvider, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    /// A token valid for at least ``refreshMargin``.
    func get() async throws -> String {
        if let token, isFresh(expiresAt) { return token }
        return try await refresh()
    }

    /// Fetches a new token even if the cached one looks valid. Joins a refresh
    /// already in flight.
    func refresh() async throws -> String {
        if let inFlight { return try await inFlight.value }

        let provider = self.provider
        let task = Task { try await provider() }
        inFlight = task
        defer { inFlight = nil }

        let fresh = try await task.value
        token = fresh
        expiresAt = TokenManager.expiry(of: fresh)
        return fresh
    }

    /// Forgets the cached token.
    func clear() {
        token = nil
        expiresAt = nil
    }

    private func isFresh(_ expiry: Date?) -> Bool {
        guard let expiry else { return true }  // no exp claim: assume usable
        return now() < expiry.addingTimeInterval(-TokenManager.refreshMargin)
    }

    /// The `exp` claim of a JWT, or nil if it has none or cannot be read.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
