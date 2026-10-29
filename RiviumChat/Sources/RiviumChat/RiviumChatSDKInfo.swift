import Foundation

/// Identity this SDK reports to the API with every request
/// (`X-Rivium-SDK: ios/<version>`).
public enum RiviumChatSDKInfo {
    /// Name of this SDK.
    public static let name = "ios"

    /// Version of this SDK. Must match `RiviumChat.podspec`; a unit test
    /// fails when they drift.
    public static let version = "0.2.0"

    /// Header that carries the SDK identity.
    static let headerName = "X-Rivium-SDK"

    /// Its value: `ios/<version>`.
    static let headerValue = "\(name)/\(version)"
}
