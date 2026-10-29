# RiviumChat iOS SDK

Real-time messaging SDK for iOS and macOS. Add chat to your app with pre-built UI components, real-time messaging, read receipts, typing indicators, reactions, and push notifications.

## Features

- Real-time messaging via WebSocket (<50ms latency)
- Pre-built UI components (chat screen, message bubbles, input field, typing indicator, etc.)
- Read receipts with delivery status (sent, delivered, read)
- Emoji reactions and message pinning
- Typing and presence indicators
- Threaded replies and swipe-to-reply
- File and image sharing with inline previews
- Full-text message search
- Unread message counts
- Push notifications via [Rivium Push](https://rivium.co/cloud/rivium-push) for offline users
- Customizable theming
- iOS 13+ (Core SDK), iOS 15+ (UI Components), macOS 10.15+

## Installation

### Swift Package Manager

Add the package URL in Xcode:

**File > Add Package Dependencies** and enter:

```
https://github.com/Rivium-co/rivium-chat-ios-sdk
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Rivium-co/rivium-chat-ios-sdk", from: "0.2.0"),
]
```

Then add the libraries to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RiviumChat", package: "rivium-chat-ios-sdk"),
        .product(name: "RiviumChatUI", package: "rivium-chat-ios-sdk"),
    ]
)
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'RiviumChat', '~> 0.2'
pod 'RiviumChatUI', '~> 0.2'
```

Then run:

```bash
pod install
```

## Quick Start

### 1. Initialize the Client

```swift
import RiviumChat
import RiviumChatUI

let config = RiviumChatConfig(
    apiKey: "your_api_key",
    userId: "user-123",
    userInfo: ["displayName": "John"]
)

let client = RiviumChatClient(config: config)
try await client.connect()
```

### Secure user identity (recommended)

Your API key ships inside the app, so on its own it cannot prove who the user
is. Add a `tokenProvider` that asks **your server** for a user token:

```swift
let config = RiviumChatConfig(
    apiKey: "your_api_key",
    userId: "user-123",
    tokenProvider: { try await myBackend.chatToken() }
)

// Revoked or invalid token — send the user to login.
client.onAuthError
    .sink { _ in signOut() }
    .store(in: &cancellables)
```

Your server mints it with the server secret (never put the secret in the app):

```http
POST https://chat.rivium.co/api/v1/users/token
x-api-key: your_api_key
x-server-secret: your_server_secret

{ "userId": "user-123" }
```

Tokens last 1 hour. The SDK refreshes them before they expire and retries a
request once if the server reports an expired token, so users never notice.

### 2. Create or Join a Room

```swift
let room = try await client.findOrCreateRoom(
    externalId: "order-123",
    participants: [
        ["externalUserId": "user-123", "displayName": "John", "role": "member"],
        ["externalUserId": "user-456", "displayName": "Jane", "role": "member"]
    ]
)
```

### 3. Send Messages

```swift
let message = try await client.sendMessage(room.id, content: "Hello!")
```

### 4. Listen for Real-Time Events

```swift
// New messages
client.onMessage.sink { message in
    print("New message: \(message.content)")
}

// Typing indicators
client.onTypingEvent.sink { event in
    print("\(event.userId) is typing: \(event.isTyping)")
}

// Presence (online/offline)
client.onPresenceChange.sink { event in
    print("\(event.userId) is online: \(event.isOnline)")
}

// Read receipts
client.onReadReceipt.sink { event in
    print("\(event.userId) read messages at \(event.readAt)")
}
```

### 5. Mark Messages as Read

```swift
try await client.markAsRead(room.id)
```

### 6. Search Messages

```swift
let result = try await client.searchMessagesWithTotal(room.id, query: "Order #1001")
print("\(result.total) matches")
for message in result.messages { print(message.content) }
```

`total` counts every match, not only this page; `hasMore` says whether another page follows (pass `limit` and `offset` to page). `searchMessages()` still returns only the list.

## Sending while offline

By default `sendMessage` throws when there is no network. Turn on the offline queue to keep such messages and send them when the connection is back, in the order written and never twice:

```swift
let client = RiviumChatClient(config: RiviumChatConfig(
    apiKey: "rv_live_demo_app",
    userId: "user-42",
    queueOfflineMessages: true
))

let message = try await client.sendMessage(roomId, content: "Order #1001 is ready")
if message.isPending {
    // Queued: shown as waiting, sent when the network is back
}

client.onMessageSent
    .sink { event in
        // event.localId (the pending id) -> event.message (the stored message)
    }
    .store(in: &cancellables)

client.onMessageFailed
    .sink { event in
        // event.reason: "expired" (waited 24 hours) or "rejected" (refused by the server)
    }
    .store(in: &cancellables)
```

- Only network failures are queued (no network, timeout, a failing `tokenProvider`, 5xx, 408, 429). Errors the server answers, such as not a member of the room or an invalid message, still throw.
- A queued message has `isPending == true`, the id `local_<clientMessageId>` and `clientMessageId`. The stored message (and its live `onMessage` event) carries the same `clientMessageId`, so you can replace the pending copy.
- The queue is sent when the realtime connection comes back, and with `retryPendingMessages()`. `getPendingMessages(roomId:)` lists what waits; `cancelPendingMessage(localId)` removes one (a message already being sent cannot be recalled). Queued messages of another user on the same device are never sent.
- Attachments must already be uploaded (URLs); uploads themselves are not queued.
- The queue lives in memory. To keep it across app restarts, add `persistOfflineMessages: true` (a file in Application Support), or pass your own `outboxStore`.

Call `client.clearPendingMessages()` on sign-out when another user may sign in on the device. The UI kit's chat screen shows queued messages as "Waiting for network…".

## Packages

| Package | Description | Min iOS |
|---------|-------------|---------|
| `RiviumChat` | Core SDK - API client, real-time messaging, models | iOS 13+ |
| `RiviumChatUI` | Pre-built UI components with theming | iOS 15+ |

## UI Components

`RiviumChatUI` includes ready-to-use SwiftUI components:

- `ChatMessageBubble` - Message bubble with read receipts, reactions, and reply preview
- `ChatInputField` - Text input with attachment and typing indicator support
- `TypingIndicator` - Animated typing dots
- `PresenceIndicator` - Online/offline status dot
- `UnreadBadge` - Unread message count badge
- `MessageReactionPicker` - Emoji reaction selector
- `ChatRoomListTile` - Room list item with last message preview
- `ReadReceipts` - Delivery status indicators (sent, delivered, read)
- `SwipeableMessage` - Swipe-to-reply gesture
- `MessageSearchBar` - Full-text message search

## Example App

The `ios_ecommerce/` directory contains a complete e-commerce chat example demonstrating:

- Buyer/seller chat for order support
- Real-time messaging with read receipts
- Typing and presence indicators
- Emoji reactions and message pinning
- Push notifications (via Rivium Push)
- Unread message badges
- Message pagination
- Reply to messages

To run it, open `ios_ecommerce/RiviumChatEcommerce/RiviumChatEcommerceApp.swift` and replace the placeholder in `ExampleConfig.apiKey` with your project's public key (`rv_live_...`) from [Rivium Console](https://console.rivium.co). Keep your real key out of version control.

## Push Notifications

RiviumChat integrates with [Rivium Push](https://rivium.co/cloud/rivium-push) for offline push notifications. See the example app for integration details.

```swift
import RiviumPush

// Initialize push
let pushConfig = RiviumPushConfig(
    apiKey: "your_api_key",
    showNotificationInForeground: true
)
RiviumPush.shared.initialize(config: pushConfig)
RiviumPush.shared.register(userId: "user-123")
```

## Links

- [Rivium Chat](https://rivium.co/cloud/rivium-chat) - Learn more about Rivium Chat
- [Documentation](https://rivium.co/cloud/rivium-chat/docs/quick-start) - Full documentation and guides
- [Rivium Console](https://console.rivium.co) - Manage your chat rooms

## License

MIT
