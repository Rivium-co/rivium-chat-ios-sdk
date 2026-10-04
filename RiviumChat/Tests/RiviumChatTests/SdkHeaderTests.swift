import XCTest
@testable import RiviumChat

/// Answers every request with an empty list and keeps what was sent.
private final class RecordingProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SdkHeaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RecordingProtocol.reset()
    }

    private func api(tokenProvider: ChatTokenProvider? = nil) -> ApiService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        let config = RiviumChatConfig(apiKey: "rv_live_test", userId: "alice", tokenProvider: tokenProvider)
        return ApiService(config: config, sessionConfiguration: configuration)
    }

    func testEveryRequestSendsTheSdkHeader() async throws {
        _ = try await api().listRooms("alice")

        XCTAssertEqual(RecordingProtocol.requests.count, 1)
        let request = try XCTUnwrap(RecordingProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rivium-SDK"), "ios/\(RiviumChatSDKInfo.version)")
        // Nothing else about the request changed.
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "rv_live_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-user-token"))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://chat.rivium.co/api/v1/rooms?userId=alice")
        let sent = Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() })
        XCTAssertEqual(sent, ["x-api-key", "content-type", "x-rivium-sdk"])
    }

    func testItIsSentTogetherWithTheUserToken() async throws {
        _ = try await api(tokenProvider: { "a.b.c" }).listRooms("alice")

        let request = try XCTUnwrap(RecordingProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Rivium-SDK"), "ios/\(RiviumChatSDKInfo.version)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-token"), "a.b.c")
    }

    func testVersionMatchesThePodspec() throws {
        XCTAssertEqual(RiviumChatSDKInfo.name, "ios")
        // …/RiviumChat/Tests/RiviumChatTests/SdkHeaderTests.swift → the repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let podspec = try String(contentsOf: root.appendingPathComponent("RiviumChat.podspec"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"s\.version\s*=\s*'([^']+)'"#)
        let match = try XCTUnwrap(regex.firstMatch(in: podspec, range: NSRange(podspec.startIndex..., in: podspec)))
        let version = String(podspec[try XCTUnwrap(Range(match.range(at: 1), in: podspec))])
        XCTAssertEqual(RiviumChatSDKInfo.version, version)
    }
}
