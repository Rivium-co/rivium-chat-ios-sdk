import XCTest
@testable import RiviumChat

final class RiviumChatTests: XCTestCase {
    func testConfigInitialization() {
        let config = RiviumChatConfig(
            apiKey: "test-api-key",
            userId: "test-user-id",
            userInfo: ["displayName": "Test User"]
        )

        XCTAssertEqual(config.apiKey, "test-api-key")
        XCTAssertEqual(config.userId, "test-user-id")
        XCTAssertEqual(config.userInfo?["displayName"], "Test User")
    }

    func testMessageDecoding() throws {
        let json = """
        {
            "id": "msg-123",
            "roomId": "room-456",
            "senderUserId": "user-789",
            "content": "Hello, world!",
            "type": "text",
            "isDeleted": false,
            "createdAt": "2024-01-15T10:30:00Z",
            "isEdited": false,
            "isPinned": false
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(message.id, "msg-123")
        XCTAssertEqual(message.roomId, "room-456")
        XCTAssertEqual(message.senderUserId, "user-789")
        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertEqual(message.type, .text)
        XCTAssertFalse(message.isDeleted)
        XCTAssertFalse(message.isEdited)
        XCTAssertFalse(message.isPinned)
    }

    func testRoomDecoding() throws {
        let json = """
        {
            "id": "room-123",
            "type": "direct",
            "externalId": "consultation-456",
            "isActive": true,
            "participants": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let room = try decoder.decode(Room.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(room.id, "room-123")
        XCTAssertEqual(room.type, .direct)
        XCTAssertEqual(room.externalId, "consultation-456")
        XCTAssertTrue(room.isActive)
        XCTAssertTrue(room.participants.isEmpty)
    }
}
