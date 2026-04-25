import SwiftUI

/// A compact header widget that displays order information in the chat screen.
public struct OrderHeaderWidget: View {
    let order: Order

    public init(order: Order) {
        self.order = order
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Order image
            AsyncImage(url: URL(string: order.primaryImage ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(
                        Image(systemName: "bag.fill")
                            .foregroundColor(.accentColor)
                    )
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Order details
            VStack(alignment: .leading, spacing: 2) {
                Text(order.orderNumber)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                Text("\(order.itemCount) item\(order.itemCount > 1 ? "s" : "") • \(order.formattedTotal)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Status badge
                OrderStatusBadge(status: order.status)
            }

            Spacer()

            // Tracking info (if shipped)
            if order.trackingNumber != nil && order.status == .shipped {
                VStack(spacing: 2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption)
                        .foregroundColor(order.status.color)
                    Text("In Transit")
                        .font(.caption2)
                        .foregroundColor(order.status.color)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

/// Status badge for orders.
public struct OrderStatusBadge: View {
    let status: OrderStatus

    public init(status: OrderStatus) {
        self.status = status
    }

    public var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .cornerRadius(4)
    }
}

/// A larger order card for the orders list.
public struct OrderListCard: View {
    let order: Order
    var unreadCount: Int = 0
    let onTap: () -> Void

    public init(order: Order, unreadCount: Int = 0, onTap: @escaping () -> Void) {
        self.order = order
        self.unreadCount = unreadCount
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Order image
                AsyncImage(url: URL(string: order.primaryImage ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            Image(systemName: "bag.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        )
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Order details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(order.orderNumber)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        // Unread badge
                        if unreadCount > 0 {
                            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }

                    // Items summary
                    let itemsSummary = order.items.prefix(2).map { $0.name }.joined(separator: ", ")
                    let moreText = order.items.count > 2 ? " +\(order.items.count - 2) more" : ""
                    Text(itemsSummary + moreText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    HStack {
                        OrderStatusBadge(status: order.status)

                        Spacer()

                        Text(order.formattedTotal)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
