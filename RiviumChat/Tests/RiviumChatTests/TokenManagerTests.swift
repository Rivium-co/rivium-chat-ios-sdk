import XCTest
@testable import RiviumChat

final class TokenManagerTests: XCTestCase {

    /// A JWT-shaped token expiring at `exp`; only the payload matters here.
    private func jwt(_ id: String, expiresIn seconds: TimeInterval) -> String {
        func b64(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let exp = Date().addingTimeInterval(seconds).timeIntervalSince1970
        return "\(b64(["alg": "HS256"])).\(b64(["sub": id, "exp": exp])).sig"
    }

    /// Counts provider calls across concurrent access.
    private actor Counter {
        private(set) var count = 0
        func next() -> Int { count += 1; return count }
    }

    func testReusesCachedToken() async throws {
        let counter = Counter()
        let manager = TokenManager(provider: { [self] in jwt("t\(await counter.next())", expiresIn: 3600) })

        let first = try await manager.get()
        let second = try await manager.get()

        XCTAssertEqual(first, second)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    func testRefreshesTokenAboutToExpire() async throws {
        let counter = Counter()
        let manager = TokenManager(provider: { [self] in
            let n = await counter.next()
            // The first token expires inside the 60 s refresh margin.
            return jwt("t\(n)", expiresIn: n == 1 ? 30 : 3600)
        })

        _ = try await manager.get()
        _ = try await manager.get()

        let calls = await counter.count
        XCTAssertEqual(calls, 2)
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        let counter = Counter()
        let manager = TokenManager(provider: { [self] in
            _ = await counter.next()
            try await Task.sleep(nanoseconds: 50_000_000)
            return jwt("t", expiresIn: 3600)
        })

        let tokens = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<8 { group.addTask { try await manager.get() } }
            var all: [String] = []
            for try await token in group { all.append(token) }
            return all
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(Set(tokens).count, 1)
    }

    func testClearForcesNewToken() async throws {
        let counter = Counter()
        let manager = TokenManager(provider: { [self] in jwt("t\(await counter.next())", expiresIn: 3600) })

        _ = try await manager.get()
        await manager.clear()
        _ = try await manager.get()

        let calls = await counter.count
        XCTAssertEqual(calls, 2)
    }

    func testExpiryReadsExpAndToleratesJunk() {
        let token = jwt("x", expiresIn: 3600)
        let expiry = TokenManager.expiry(of: token)
        XCTAssertNotNil(expiry)
        XCTAssertEqual(expiry!.timeIntervalSinceNow, 3600, accuracy: 5)
        XCTAssertNil(TokenManager.expiry(of: "not-a-jwt"))
    }

    func testProviderErrorPropagates() async {
        struct Boom: Error {}
        let manager = TokenManager(provider: { throw Boom() })

        do {
            _ = try await manager.get()
            XCTFail("expected the provider error to surface")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}
