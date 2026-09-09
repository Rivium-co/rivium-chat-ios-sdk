# Changelog

## [0.1.1] - 2026-09-09

- Fixed: subscribing to a room could throw "Subscription to a channel already exists" after leaving and rejoining it.
- Fixed: unsubscribing removed the subscription from the client without unsubscribing, so the server still considered the client subscribed.
- Fixed: `subscribeRoom` could report success while a channel had not subscribed, leaving the room without live updates.
- Fixed: presence and typing channels reported nothing when a subscribe failed.
- Added: `isRoomSubscribed()` and `subscribedChannelsFor()` to check subscription state.
- Added: `reconnect()` to recover a stale connection.

## [0.1.0] - 2026-04-26

- Initial release
