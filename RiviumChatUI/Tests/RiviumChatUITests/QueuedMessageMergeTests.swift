import XCTest
import RiviumChat
@testable import RiviumChatUI

/// A message queued offline is shown once: waiting, then replaced, never twice.
final class QueuedMessageMergeTests: XCTestCase {

    private func queued(_ cmid: String, _ content: String = "Order #1001 is ready") -> Message {
        Message(id: "local_\(cmid)", roomId: "room-1", senderUserId: "user-42", content: content,
                createdAt: Date(), isPending: true, clientMessageId: cmid)
    }

    private func stored(_ id: String, _ cmid: String?, _ content: String = "Order #1001 is ready") -> Message {
        Message(id: id, roomId: "room-1", senderUserId: "user-42", content: content,
                createdAt: Date(), clientMessageId: cmid)
    }

    func testAQueuedMessageShowsAsWaitingForNetworkNotFailed() {
        XCTAssertTrue(QueuedMessageMerge.isQueuedOffline(queued("abc")))
        XCTAssertFalse(queued("abc").isFailed)
        XCTAssertFalse(QueuedMessageMerge.isQueuedOffline(queued("abc").withState(isPending: true, isFailed: false, id: "pending_1")))
    }

    func testSendResultQueuedReplacesTheOptimisticCopy() {
        var list = [queued("x").withState(isPending: true, isFailed: false, id: "pending_1")]
        QueuedMessageMerge.applySendResult(&list, placeholderId: "pending_1", sent: queued("abc"))
        XCTAssertEqual(list.map(\.id), ["local_abc"])
    }

    func testMessageSentReplacesTheWaitingCopyThenLiveEventUpdatesInPlace() {
        var list = [queued("abc")]
        QueuedMessageMerge.mergeSent(&list, localId: "local_abc", message: stored("m-1", "abc"))
        XCTAssertEqual(list.map(\.id), ["m-1"])
        QueuedMessageMerge.mergeLive(&list, stored("m-1", "abc"))
        XCTAssertEqual(list.map(\.id), ["m-1"])
    }

    func testLiveEventFirstThenMessageSentShownOnce() {
        var list = [stored("m-0", nil, "older"), queued("abc")]
        QueuedMessageMerge.mergeLive(&list, stored("m-1", "abc"))
        XCTAssertEqual(list.map(\.id), ["m-0", "m-1"])
        QueuedMessageMerge.mergeSent(&list, localId: "local_abc", message: stored("m-1", "abc"))
        XCTAssertEqual(list.map(\.id), ["m-0", "m-1"])
    }

    func testAQueuedCopyIsNotTakenByAnotherMessageWithTheSameText() {
        var list = [queued("abc", "ok")]
        QueuedMessageMerge.mergeLive(&list, stored("m-5", nil, "ok"))
        XCTAssertEqual(list.map(\.id), ["m-5", "local_abc"])
    }

    func testMessageFailedMarksTheCopyFailedSoRetryShows() {
        var list = [queued("abc")]
        QueuedMessageMerge.markFailed(&list, localId: "local_abc")
        XCTAssertTrue(list[0].isFailed)
        XCTAssertFalse(list[0].isPending)
    }
}
