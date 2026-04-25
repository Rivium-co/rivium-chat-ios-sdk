import SwiftUI

/// Online/offline presence indicator dot
public struct PresenceIndicator: View {
    let isOnline: Bool
    var size: CGFloat = 12
    var showBorder: Bool = true
    var borderColor: Color = Color(UIColor.systemBackground)

    @Environment(\.riviumChatColors) private var colors

    public init(
        isOnline: Bool,
        size: CGFloat = 12,
        showBorder: Bool = true,
        borderColor: Color = Color(UIColor.systemBackground)
    ) {
        self.isOnline = isOnline
        self.size = size
        self.showBorder = showBorder
        self.borderColor = borderColor
    }

    public var body: some View {
        Circle()
            .fill(isOnline ? colors.onlineIndicator : colors.offlineIndicator)
            .frame(width: size, height: size)
            .overlay(
                showBorder ?
                Circle()
                    .stroke(borderColor, lineWidth: 2)
                : nil
            )
            .animation(.easeInOut(duration: 0.3), value: isOnline)
    }
}

/// Presence status with text label
public struct PresenceStatus: View {
    let isOnline: Bool

    @Environment(\.riviumChatColors) private var colors

    public init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? colors.onlineIndicator : colors.offlineIndicator)
                .frame(width: 8, height: 8)

            Text(isOnline ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(isOnline ? colors.onlineIndicator : colors.offlineIndicator)
        }
        .animation(.easeInOut(duration: 0.3), value: isOnline)
    }
}
