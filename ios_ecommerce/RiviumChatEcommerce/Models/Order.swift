import Foundation
import SwiftUI

/// Represents an e-commerce order.
public struct Order: Identifiable {
    public let id: String
    public let orderNumber: String
    public let status: OrderStatus
    public let items: [OrderItem]
    public let buyerId: String
    public let sellerId: String
    public let createdAt: Date
    public let totalAmount: Decimal
    public let shippingAddress: String?
    public let trackingNumber: String?

    public var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    public var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: totalAmount as NSDecimalNumber) ?? "$0.00"
    }

    public var primaryImage: String? {
        items.first?.imageUrl
    }

    public init(
        id: String,
        orderNumber: String,
        status: OrderStatus,
        items: [OrderItem],
        buyerId: String,
        sellerId: String,
        createdAt: Date,
        totalAmount: Decimal,
        shippingAddress: String? = nil,
        trackingNumber: String? = nil
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.status = status
        self.items = items
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.createdAt = createdAt
        self.totalAmount = totalAmount
        self.shippingAddress = shippingAddress
        self.trackingNumber = trackingNumber
    }
}

/// Represents an item in an order.
public struct OrderItem: Identifiable {
    public let id: String
    public let name: String
    public let quantity: Int
    public let price: Decimal
    public let imageUrl: String?

    public init(id: String, name: String, quantity: Int, price: Decimal, imageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.price = price
        self.imageUrl = imageUrl
    }
}

/// Order status enum.
public enum OrderStatus: String, CaseIterable {
    case pending = "PENDING"
    case confirmed = "CONFIRMED"
    case shipped = "SHIPPED"
    case delivered = "DELIVERED"
    case cancelled = "CANCELLED"

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    public var color: Color {
        switch self {
        case .pending: return .orange
        case .confirmed: return .blue
        case .shipped: return .purple
        case .delivered: return .green
        case .cancelled: return .red
        }
    }
}

/// Mock orders for demo purposes.
public struct MockOrders {
    public static let orders: [Order] = {
        let now = Date()
        let calendar = Calendar.current

        return [
            Order(
                id: "order-001",
                orderNumber: "ORD-2024-001",
                status: .shipped,
                items: [
                    OrderItem(
                        id: "item-001",
                        name: "Wireless Bluetooth Headphones",
                        quantity: 1,
                        price: 79.99,
                        imageUrl: "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=200"
                    ),
                    OrderItem(
                        id: "item-002",
                        name: "Phone Case",
                        quantity: 2,
                        price: 15.99,
                        imageUrl: "https://images.unsplash.com/photo-1601784551446-20c9e07cdbdb?w=200"
                    )
                ],
                buyerId: DemoUsers.buyer.id,
                sellerId: DemoUsers.seller.id,
                createdAt: calendar.date(byAdding: .day, value: -2, to: now)!,
                totalAmount: 111.97,
                shippingAddress: "123 Main St, New York, NY 10001",
                trackingNumber: "1Z999AA10123456784"
            ),
            Order(
                id: "order-002",
                orderNumber: "ORD-2024-002",
                status: .confirmed,
                items: [
                    OrderItem(
                        id: "item-003",
                        name: "Smart Watch Pro",
                        quantity: 1,
                        price: 299.99,
                        imageUrl: "https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=200"
                    )
                ],
                buyerId: DemoUsers.buyer.id,
                sellerId: DemoUsers.seller.id,
                createdAt: calendar.date(byAdding: .day, value: -1, to: now)!,
                totalAmount: 299.99,
                shippingAddress: "456 Oak Ave, Los Angeles, CA 90001"
            ),
            Order(
                id: "order-003",
                orderNumber: "ORD-2024-003",
                status: .pending,
                items: [
                    OrderItem(
                        id: "item-004",
                        name: "Laptop Stand",
                        quantity: 1,
                        price: 49.99,
                        imageUrl: "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=200"
                    ),
                    OrderItem(
                        id: "item-005",
                        name: "USB-C Hub",
                        quantity: 1,
                        price: 39.99,
                        imageUrl: "https://images.unsplash.com/photo-1625723044792-44de16ccb4e9?w=200"
                    ),
                    OrderItem(
                        id: "item-006",
                        name: "Wireless Mouse",
                        quantity: 1,
                        price: 29.99,
                        imageUrl: "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=200"
                    )
                ],
                buyerId: DemoUsers.buyer.id,
                sellerId: DemoUsers.seller.id,
                createdAt: calendar.date(byAdding: .hour, value: -3, to: now)!,
                totalAmount: 119.97,
                shippingAddress: "789 Pine Rd, Chicago, IL 60601"
            ),
            Order(
                id: "order-004",
                orderNumber: "ORD-2024-004",
                status: .delivered,
                items: [
                    OrderItem(
                        id: "item-007",
                        name: "Mechanical Keyboard",
                        quantity: 1,
                        price: 149.99,
                        imageUrl: "https://images.unsplash.com/photo-1511467687858-23d96c32e4ae?w=200"
                    )
                ],
                buyerId: DemoUsers.buyer.id,
                sellerId: DemoUsers.seller.id,
                createdAt: calendar.date(byAdding: .day, value: -7, to: now)!,
                totalAmount: 149.99,
                shippingAddress: "321 Elm St, Seattle, WA 98101",
                trackingNumber: "1Z999AA10123456785"
            ),
            Order(
                id: "order-005",
                orderNumber: "ORD-2024-005",
                status: .cancelled,
                items: [
                    OrderItem(
                        id: "item-008",
                        name: "Gaming Chair",
                        quantity: 1,
                        price: 249.99,
                        imageUrl: "https://images.unsplash.com/photo-1598550476439-6847785fcea6?w=200"
                    )
                ],
                buyerId: DemoUsers.buyer.id,
                sellerId: DemoUsers.seller.id,
                createdAt: calendar.date(byAdding: .day, value: -5, to: now)!,
                totalAmount: 249.99,
                shippingAddress: "555 Maple Dr, Miami, FL 33101"
            )
        ]
    }()

    public static func getById(_ id: String) -> Order? {
        orders.first { $0.id == id }
    }
}
