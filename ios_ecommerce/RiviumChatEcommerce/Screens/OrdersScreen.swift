import SwiftUI
import UserNotifications
import RiviumChat
import RiviumChatUI

/// Screen showing list of orders with chat integration.
public struct OrdersScreen: View {
    let currentUser: DemoUser
    let client: RiviumChatClient
    let onOrderTap: (Order) -> Void
    let onLogout: () -> Void

    @State private var isLoading = true
    @State private var unreadCounts: [String: Int] = [:]
    /// Maps roomId -> order externalId for rooms we've subscribed to
    @State private var roomToOrderMap: [String: String] = [:]
    @State private var subscribedRoomIds: Set<String> = []

    private var orders: [Order] {
        MockOrders.orders.filter { order in
            switch currentUser.role {
            case .buyer:
                return order.buyerId == currentUser.id
            case .seller:
                return order.sellerId == currentUser.id
            }
        }
    }

    public init(
        currentUser: DemoUser,
        client: RiviumChatClient,
        onOrderTap: @escaping (Order) -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.currentUser = currentUser
        self.client = client
        self.onOrderTap = onOrderTap
        self.onLogout = onLogout
    }

    public var body: some View {
        Group {
            if orders.isEmpty {
                emptyState
            } else {
                ordersList
            }
        }
        .navigationTitle("My Orders")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 8) {
                    AsyncImage(url: URL(string: currentUser.avatarUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .overlay(
                                Image(systemName: currentUser.role == .buyer ? "person.fill" : "storefront.fill")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            )
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    Text(currentUser.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .task {
            await requestNotificationPermission()
            await loadUnreadCountsAndSubscribe()
        }
        .onAppear {
            Task {
                await refreshUnreadCounts()
                // Re-observe rooms that may have been unsubscribed by OrderChatScreen
                for (roomId, _) in roomToOrderMap {
                    client.observeRoom(roomId)
                }
            }
        }
        .onReceive(client.onMessage) { message in
            // When a new message arrives from the other user, increment unread count
            if message.senderUserId != currentUser.id,
               let orderId = roomToOrderMap[message.roomId] {
                unreadCounts[orderId, default: 0] += 1
            }
        }
    }

    private var ordersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(orders) { order in
                    OrderListCard(
                        order: order,
                        unreadCount: unreadCounts[order.id] ?? 0,
                        onTap: { onOrderTap(order) }
                    )
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bag")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No orders yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Your orders will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    /// Load unread counts and subscribe to all existing rooms for real-time updates.
    private func loadUnreadCountsAndSubscribe() async {
        print("[RiviumChat] Loading unread counts for \(orders.count) orders...")

        do {
            let summary = try await client.getUnreadSummary()
            var counts: [String: Int] = [:]
            for roomUnread in summary.rooms {
                if let externalId = roomUnread.externalId {
                    counts[externalId] = roomUnread.unreadCount
                }
            }
            unreadCounts = counts
            isLoading = false
            print("[RiviumChat] Unread counts loaded: \(unreadCounts)")
        } catch {
            print("[RiviumChat] Failed to load unread counts: \(error)")
            isLoading = false
        }

        // Subscribe to chat channels for all existing rooms to get real-time message events
        for order in orders {
            do {
                let room = try await client.getRoomByExternalId(order.id)
                roomToOrderMap[room.id] = order.id
                if !subscribedRoomIds.contains(room.id) {
                    client.observeRoom(room.id)
                    subscribedRoomIds.insert(room.id)
                }
            } catch {
                // Room doesn't exist yet for this order
            }
        }
    }

    /// Request notification permission if not already granted.
    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Refresh unread counts only (e.g. when returning from chat).
    private func refreshUnreadCounts() async {
        do {
            let summary = try await client.getUnreadSummary()
            var counts: [String: Int] = [:]
            for roomUnread in summary.rooms {
                if let externalId = roomUnread.externalId {
                    counts[externalId] = roomUnread.unreadCount
                }
            }
            unreadCounts = counts
        } catch {
            // Ignore refresh errors
        }
    }
}
