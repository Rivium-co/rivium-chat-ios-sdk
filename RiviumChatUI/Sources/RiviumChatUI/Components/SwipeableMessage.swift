import SwiftUI

/// A container view that adds swipe-to-reply gesture to its content.
public struct SwipeableMessage<Content: View>: View {
    let content: Content
    let onSwipeToReply: () -> Void
    var swipeThreshold: CGFloat = 80
    var swipeColor: Color = .accentColor

    @State private var offset: CGFloat = 0
    @State private var isTriggered = false

    public init(
        onSwipeToReply: @escaping () -> Void,
        swipeThreshold: CGFloat = 80,
        swipeColor: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onSwipeToReply = onSwipeToReply
        self.swipeThreshold = swipeThreshold
        self.swipeColor = swipeColor
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Reply indicator
            HStack {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundColor(swipeColor)
                    .opacity(min(1, offset / swipeThreshold))
                    .scaleEffect(min(1, offset / swipeThreshold))
                    .padding(.leading, 16)
                Spacer()
            }

            // Main content
            content
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.width
                            // Only allow swiping right
                            if translation > 0 {
                                offset = min(translation, swipeThreshold * 1.2)

                                // Haptic feedback when threshold is crossed
                                if offset >= swipeThreshold && !isTriggered {
                                    isTriggered = true
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                } else if offset < swipeThreshold {
                                    isTriggered = false
                                }
                            }
                        }
                        .onEnded { _ in
                            if offset >= swipeThreshold {
                                onSwipeToReply()
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = 0
                                isTriggered = false
                            }
                        }
                )
        }
    }
}

/// Extension to add swipe-to-reply to any view.
public extension View {
    func swipeToReply(
        threshold: CGFloat = 80,
        color: Color = .accentColor,
        onReply: @escaping () -> Void
    ) -> some View {
        SwipeableMessage(
            onSwipeToReply: onReply,
            swipeThreshold: threshold,
            swipeColor: color
        ) {
            self
        }
    }
}
