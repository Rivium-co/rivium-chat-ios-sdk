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
    .package(url: "https://github.com/Rivium-co/rivium-chat-ios-sdk", from: "0.1.0"),
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
pod 'RiviumChat', '~> 0.1'
pod 'RiviumChatUI', '~> 0.1'
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
