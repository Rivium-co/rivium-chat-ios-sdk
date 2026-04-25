import SwiftUI
import Combine
import RiviumChat

/// Environment key for RiviumChatClient
private struct RiviumChatClientKey: EnvironmentKey {
    static let defaultValue: RiviumChatClient? = nil
}

extension EnvironmentValues {
    /// Access the RiviumChatClient from the environment
    public var riviumChatClient: RiviumChatClient? {
        get { self[RiviumChatClientKey.self] }
        set { self[RiviumChatClientKey.self] = newValue }
    }
}

/// Observable wrapper for RiviumChatClient that manages lifecycle and connection state
@MainActor
public final class RiviumChatClientWrapper: ObservableObject {
    /// The underlying RiviumChatClient instance
    public let client: RiviumChatClient

    /// Current connection state
    @Published public private(set) var isConnected = false

    /// Connection error if any
    @Published public private(set) var connectionError: Error?

    private var cancellables = Set<AnyCancellable>()

    public init(config: RiviumChatConfig) {
        self.client = RiviumChatClient(config: config)

        // Observe connection state
        client.onConnectionStateChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isConnected = state == .connected
                if state == .error {
                    self?.connectionError = NSError(domain: "RiviumChat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
                }
            }
            .store(in: &cancellables)
    }

    /// Connect to the RiviumChat server
    public func connect() async throws {
        try await client.connect()
    }

    /// Disconnect from the server
    public func disconnect() {
        client.disconnect()
    }

    deinit {
        client.dispose()
    }
}

/// Provides RiviumChatClient to the view hierarchy and manages its lifecycle
public struct RiviumChatScope<Content: View>: View {
    @StateObject private var wrapper: RiviumChatClientWrapper
    private let autoConnect: Bool
    private let onConnected: (() -> Void)?
    private let onConnectionError: ((Error) -> Void)?
    private let content: () -> Content

    /// Creates a RiviumChatScope that provides a client to child views
    /// - Parameters:
    ///   - config: The RiviumChat configuration
    ///   - autoConnect: Whether to connect automatically on appear
    ///   - onConnected: Callback when connection is established
    ///   - onConnectionError: Callback when connection fails
    ///   - content: The child views
    public init(
        config: RiviumChatConfig,
        autoConnect: Bool = true,
        onConnected: (() -> Void)? = nil,
        onConnectionError: ((Error) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _wrapper = StateObject(wrappedValue: RiviumChatClientWrapper(config: config))
        self.autoConnect = autoConnect
        self.onConnected = onConnected
        self.onConnectionError = onConnectionError
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.riviumChatClient, wrapper.client)
            .environmentObject(wrapper)
            .task {
                if autoConnect {
                    do {
                        try await wrapper.connect()
                        onConnected?()
                    } catch {
                        onConnectionError?(error)
                    }
                }
            }
    }
}

/// Alternative provider for when you manage the client lifecycle externally
public struct RiviumChatProvider<Content: View>: View {
    private let client: RiviumChatClient
    private let content: () -> Content

    /// Creates a provider with an existing client
    /// - Parameters:
    ///   - client: The pre-configured RiviumChatClient
    ///   - content: The child views
    public init(
        client: RiviumChatClient,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.client = client
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.riviumChatClient, client)
    }
}
