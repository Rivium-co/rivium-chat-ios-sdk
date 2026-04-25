import SwiftUI
import RiviumChat
import RiviumChatUI
import RiviumPush

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        RiviumPush.shared.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[RiviumPush] Failed to register for APNs: \(error)")
    }
}

/// Main entry point for the RiviumChat E-commerce example app.
@main
public struct RiviumChatEcommerceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var currentUser: DemoUser?
    @State private var riviumChatClient: RiviumChatClient?
    @State private var selectedOrder: Order?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        Group {
            if let user = currentUser, let client = riviumChatClient {
                NavigationStack(path: $navigationPath) {
                    OrdersScreen(
                        currentUser: user,
                        client: client,
                        onOrderTap: { order in
                            selectedOrder = order
                            navigationPath.append(order.id)
                        },
                        onLogout: logout
                    )
                    .navigationDestination(for: String.self) { orderId in
                        if let order = MockOrders.getById(orderId) {
                            OrderChatScreen(
                                order: order,
                                currentUser: user,
                                client: client,
                                onBack: {
                                    navigationPath.removeLast()
                                }
                            )
                        }
                    }
                }
            } else {
                LoginScreen(onLogin: login)
            }
        }
    }

    private func login(user: DemoUser) {
        currentUser = user
        let config = RiviumChatConfig(
            apiKey: "rv_live_64e0ada5eeb66e3adf6136337802a5a34713ce4966372854",
            userId: user.id,
            userInfo: ["displayName": user.name]
        )
        print("[RiviumChat] Creating client for user: \(user.id) (\(user.name))")
        let client = RiviumChatClient(config: config)
        riviumChatClient = client
        let pushConfig = RiviumPushConfig(apiKey: "rv_live_64e0ada5eeb66e3adf6136337802a5a34713ce4966372854", showNotificationInForeground: true)
        RiviumPush.shared.initialize(config: pushConfig)
        RiviumPush.shared.register(userId: user.id, metadata: ["displayName": user.name, "role": user.role.rawValue])
        Task {
            do {
                print("[RiviumChat] Connecting...")
                try await client.connect()
                print("[RiviumChat] Connected successfully!")
            } catch {
                print("[RiviumChat] Connection failed: \(error)")
            }
        }
    }

    private func logout() {
        RiviumPush.shared.unregister()
        riviumChatClient?.disconnect()
        riviumChatClient = nil
        currentUser = nil
        selectedOrder = nil
        navigationPath = NavigationPath()
    }
}
