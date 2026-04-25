import SwiftUI

/// Badge showing unread message count
public struct UnreadBadge: View {
    let count: Int
    var maxCount: Int = 99
    var backgroundColor: Color? = nil
    var textColor: Color = .white
    var minSize: CGFloat = 20

    public init(
        count: Int,
        maxCount: Int = 99,
        backgroundColor: Color? = nil,
        textColor: Color = .white,
        minSize: CGFloat = 20
    ) {
        self.count = count
        self.maxCount = maxCount
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.minSize = minSize
    }

    public var body: some View {
        if count > 0 {
            let displayText = count > maxCount ? "\(maxCount)+" : "\(count)"
            let isLargeNumber = displayText.count > 2

            Text(displayText)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(textColor)
                .padding(.horizontal, isLargeNumber ? 6 : 0)
                .frame(minWidth: minSize, minHeight: minSize)
                .background(backgroundColor ?? Color.red)
                .clipShape(isLargeNumber ? AnyShape(Capsule()) : AnyShape(Circle()))
        }
    }
}

/// Small dot indicator for unread status without count
public struct UnreadDot: View {
    let hasUnread: Bool
    var size: CGFloat = 8
    var color: Color = .red

    public init(
        hasUnread: Bool,
        size: CGFloat = 8,
        color: Color = .red
    ) {
        self.hasUnread = hasUnread
        self.size = size
        self.color = color
    }

    public var body: some View {
        if hasUnread {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

// Helper for type-erased shapes
struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}
