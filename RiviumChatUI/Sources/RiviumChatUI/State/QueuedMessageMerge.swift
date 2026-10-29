import Foundation
import RiviumChat

/// Keeps a message the offline outbox queued on screen exactly once:
/// "Waiting for network…", then the stored message, or failed with Retry.
enum QueuedMessageMerge {
    /// Label of a message the offline outbox keeps until the network is back.
    static let waitingForNetwork = "Waiting for network\u{2026}"

    /// A pending message the SDK queued while offline (id `local_<clientMessageId>`).
    static func isQueuedOffline(_ message: Message) -> Bool {
        message.isPending && message.id.hasPrefix(PendingMessage.localIdPrefix)
    }

    /// The answer of `sendMessage` for the optimistic copy `placeholderId`:
    /// a queued (pending) message replaces it; a stored one replaces it,
    /// unless the live event already showed it (then the copy goes).
    static func applySendResult(_ messages: inout [Message], placeholderId: String, sent: Message) {
        if !sent.isPending, let cmid = sent.clientMessageId,
           messages.contains(where: { $0.id != placeholderId && !$0.isPending && $0.clientMessageId == cmid }) {
            messages.removeAll { $0.id == placeholderId }
            if let i = messages.firstIndex(where: { $0.clientMessageId == cmid }) { messages[i] = sent }
            return
        }
        if let i = messages.firstIndex(where: { $0.id == placeholderId }) {
            messages[i] = sent
        } else if let i = messages.firstIndex(where: { $0.id == sent.id }) {
            messages[i] = sent
        } else if sent.isPending {
            messages.insert(sent, at: 0)
        }
    }

    /// A live message event: updates the copy already shown (same id, the
    /// message queued offline with the same clientMessageId, or the
    /// optimistic copy with the same sender and text), else adds it on top.
    static func mergeLive(_ messages: inout [Message], _ message: Message) {
        let existing = messages.firstIndex(where: { $0.id == message.id })
        let queued = message.clientMessageId.flatMap { cmid in
            messages.firstIndex(where: { $0.id != message.id && $0.clientMessageId == cmid })
        }
        if let existing {
            messages[existing] = message
            if let queued { messages.remove(at: queued) }
        } else if let queued {
            messages[queued] = message
        } else if let pending = messages.firstIndex(where: {
            $0.isPending && !$0.id.hasPrefix(PendingMessage.localIdPrefix) &&
                $0.content == message.content && $0.senderUserId == message.senderUserId
        }) {
            // The realtime event arrived before the API response
            messages[pending] = message
        } else {
            messages.insert(message, at: 0)
        }
    }

    /// The outbox stored a queued message: replaces its waiting copy, or
    /// drops that copy when the live event already showed the message.
    static func mergeSent(_ messages: inout [Message], localId: String, message: Message) {
        let shown = messages.firstIndex(where: {
            $0.id == message.id ||
                (!$0.isPending && message.clientMessageId != nil && $0.clientMessageId == message.clientMessageId)
        })
        let local = messages.firstIndex(where: { $0.id == localId })
        if shown != nil {
            if let local, local != shown { messages.remove(at: local) }
            if let i = messages.firstIndex(where: { $0.id == message.id }) { messages[i] = message }
        } else if let local {
            messages[local] = message
        } else {
            messages.insert(message, at: 0)
        }
    }

    /// A queued message left the queue unsent: failed, with Retry.
    static func markFailed(_ messages: inout [Message], localId: String) {
        guard let i = messages.firstIndex(where: { $0.id == localId }) else { return }
        messages[i] = messages[i].withState(isPending: false, isFailed: true)
    }

    /// Adds what the outbox still holds for the room (e.g. after a restart).
    static func addQueued(_ messages: inout [Message], _ queued: [Message]) {
        for pending in queued where !messages.contains(where: {
            $0.id == pending.id || ($0.clientMessageId != nil && $0.clientMessageId == pending.clientMessageId)
        }) {
            messages.insert(pending, at: 0) // oldest first in, so the newest ends on top
        }
    }
}

extension Message {
    /// The same message with other local state flags.
    func withState(isPending: Bool, isFailed: Bool, id: String? = nil) -> Message {
        Message(
            id: id ?? self.id, roomId: roomId, senderUserId: senderUserId, content: content, type: type,
            attachments: attachments, metadata: metadata, replyToId: replyToId, replyTo: replyTo,
            isDeleted: isDeleted, createdAt: createdAt, isEdited: isEdited, editedAt: editedAt,
            editHistory: editHistory, isPinned: isPinned, pinnedAt: pinnedAt, pinnedBy: pinnedBy,
            reactions: reactions, isPending: isPending, isFailed: isFailed, clientMessageId: clientMessageId
        )
    }
}
