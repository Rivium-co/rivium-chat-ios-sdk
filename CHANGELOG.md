# Changelog

## [0.2.0] - 2026-10-30

- Added: offline sending, off by default. With `RiviumChatConfig(queueOfflineMessages: true)`, a message that cannot be sent because of the network (no network, timeout, server busy, `tokenProvider` unreachable) is kept and sent when the connection is back, in the order written and never twice. `sendMessage()` then returns it as a pending message (`isPending == true`, id `local_<clientMessageId>`) instead of throwing. Errors the server answers (not a member, invalid message, plan limit) still throw. Without the option nothing changes.
- Added: `onMessageSent` (a queued message was stored) and `onMessageFailed` (it left the queue unsent, `reason` `"expired"` after 24 hours or `"rejected"` by the server), plus `getPendingMessages(roomId:)`, `retryPendingMessages()`, `cancelPendingMessage(_:)` and `clearPendingMessages()`.
- Added: the queue is kept in memory by default; `persistOfflineMessages: true` keeps it in a file in Application Support across app restarts, or pass `outboxStore` for your own storage (`OutboxStore`).
- Added: `Message.clientMessageId`.
- UI kit: with `queueOfflineMessages` on, a message written offline shows "Waiting for network…" and turns into the sent message once it is stored (shown once); if it cannot be sent it shows Retry.
- Fixed: `searchMessages()` failed to decode the server's answer; it now returns the matching messages. Search text with `&`, `#` or `+` is now encoded correctly.
- Fixed: dates with milliseconds, as the server sends them (`2026-10-29T10:00:00.123Z`), failed to decode before iOS 26, so rooms and messages could not be loaded. Dates are now read with or without fractional seconds.
- Fixed: user IDs, room IDs, message IDs and external IDs containing characters such as `/`, `?`, `#`, `&`, `+`, spaces or non-ASCII letters reached the server cut short or changed. Every value placed in a request URL is now encoded. An empty ID, `.` or `..` throws `RiviumChatError.invalidURL`.
- Fixed: `getMentions()` failed to decode the server's answer; it now returns the messages that mention the user.
- Fixed: the realtime connection now fetches a new token when its token expires, so long sessions stay connected.
- Fixed: a failing `tokenProvider` during `connect()` now emits `token_provider_failed` on `onAuthError`, as it already did for requests, and the connection state becomes `.error` instead of staying `.connecting`.
- Fixed: calling the client after `dispose()` crashed the app. Throwing calls now throw `RiviumChatClientDisposedError`; other calls do nothing.
- Fixed: typing indicators are throttled per room, so typing in one room no longer holds back the indicator in another.
- Changed: requires SwiftCentrifuge 0.8 or later.
- UI kit: `ChatScreen` and `ChatChannelScope` crashed when created; they now load the room from the client in the environment.
- UI kit: Edit, Pin and Unpin in the message menu now work. `ChatChannelState` gains `pinMessage(messageId:)` and `unpinMessage(messageId:)`, and pin changes from others show up live.
- UI kit: closing a chat screen no longer stops a conversation list from receiving that room's new messages.
- Added: `searchMessagesWithTotal(_:query:limit:offset:)` returns a `SearchResult` with the matching `messages`, the `total` number of matches and `hasMore`. `searchMessages()` is unchanged.
- Fixed: when the connection token cannot be fetched (unknown key, project requires a user token, no network, failing `tokenProvider`), the error is now also reported on `onConnectionError`.
- Fixed: a room subscription the server refuses (for example "Not a participant in this room") was not reported for the presence and typing channels, and the chat channel did not emit `onRecoveryFailed`. `onSubscriptionState` now carries the server's `code` and `reason` for every channel, `onConnectionError` reports the refusal, and the chat channel emits `onRecoveryFailed`. Subscription errors carry the server's code and message instead of a generic description.
- Fixed: calling `disconnect()` or `dispose()` while `connect()` was still running no longer opens a connection afterwards, and that `connect()` now ends with a `CancellationError` instead of waiting forever.
- Fixed: a possible crash when room subscriptions changed while the connection was reporting subscription events.
- UI kit: a failed message shows a Retry button, and pinned messages show a pin icon.
- UI kit: typing indicators and reply labels show the participant's display name (or their user id when they have none). `ChatChannelState` gains `participantDisplayNames` and `displayName(for:)`; `ChatInputField` gains `replyingToName` and `ChatMessageBubble` gains `replySenderName`.
- UI kit: the conversation reloads its messages when live updates were missed (`onRecoveryFailed`). `ChatChannelState` gains `refresh()`.
- UI kit: an action that fails (pin, reaction, delete) no longer replaces the conversation with "Failed to load messages".

## [0.1.4] - 2026-10-05

- Added: requests send an `X-Rivium-SDK` header (`ios/<version>`); `RiviumChatSDKInfo.version` gives the SDK version.

## [0.1.3] - 2026-09-26

- Added: `lastMessage` and `unreadCount` on `Room`. A chat list can show the
  latest message and an unread badge from `listRooms()` alone, with no extra
  calls.

## [0.1.2] - 2026-09-12

- Added: `tokenProvider` for secure user identity. Tokens are refreshed automatically before they expire and after an expired-token response.
- Added: `onAuthError` publisher for identity errors a refresh cannot fix.

## [0.1.1] - 2026-09-09

- Fixed: subscribing to a room could throw "Subscription to a channel already exists" after leaving and rejoining it.
- Fixed: unsubscribing removed the subscription from the client without unsubscribing, so the server still considered the client subscribed.
- Fixed: `subscribeRoom` could report success while a channel had not subscribed, leaving the room without live updates.
- Fixed: presence and typing channels reported nothing when a subscribe failed.
- Added: `isRoomSubscribed()` and `subscribedChannelsFor()` to check subscription state.
- Added: `reconnect()` to recover a stale connection.

## [0.1.0] - 2026-04-26

- Initial release
