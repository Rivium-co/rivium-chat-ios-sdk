import SwiftUI
import LinkPresentation

/// Data for a link preview.
public struct LinkPreviewData {
    public let url: URL
    public var title: String?
    public var description: String?
    public var imageUrl: String?
    public var siteName: String?

    public init(url: URL, title: String? = nil, description: String? = nil, imageUrl: String? = nil, siteName: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.siteName = siteName
    }
}

/// A view that displays a link preview card.
public struct LinkPreview: View {
    let data: LinkPreviewData
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?
    var isCompact: Bool = false

    @Environment(\.riviumChatColors) private var colors

    public init(
        data: LinkPreviewData,
        onTap: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        isCompact: Bool = false
    ) {
        self.data = data
        self.onTap = onTap
        self.onRemove = onRemove
        self.isCompact = isCompact
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            if isCompact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .buttonStyle(.plain)
    }

    private var compactLayout: some View {
        HStack(spacing: 12) {
            // Favicon or image placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "link")
                        .foregroundColor(.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(data.title ?? data.url.host ?? "Link")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(data.url.host ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            if data.imageUrl != nil {
                Rectangle()
                    .fill(Color(UIColor.systemGray5))
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                // Site name
                if let siteName = data.siteName {
                    Text(siteName.uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Title
                Text(data.title ?? data.url.host ?? "Link")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                // Description
                if let description = data.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // URL
                Text(data.url.host ?? "")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .background(Color(UIColor.systemBackground).clipShape(Circle()))
                }
                .padding(8)
            }
        }
    }
}

/// A view that shows link preview in the message composer.
public struct LinkPreviewComposer: View {
    @Binding var linkData: LinkPreviewData?
    var onRemove: (() -> Void)?

    public init(linkData: Binding<LinkPreviewData?>, onRemove: (() -> Void)? = nil) {
        self._linkData = linkData
        self.onRemove = onRemove
    }

    public var body: some View {
        if let data = linkData {
            LinkPreview(
                data: data,
                onRemove: {
                    linkData = nil
                    onRemove?()
                },
                isCompact: true
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Utility class to extract URLs from text.
public class LinkExtractor {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Extract URLs from text.
    public static func extractURLs(from text: String) -> [URL] {
        guard let detector = detector else { return [] }

        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count)
        )

        return matches.compactMap { $0.url }
    }

    /// Get the first URL from text.
    public static func firstURL(from text: String) -> URL? {
        extractURLs(from: text).first
    }
}

/// Service to fetch link metadata.
public class LinkMetadataService: ObservableObject {
    @Published public var metadata: LinkPreviewData?
    @Published public var isLoading = false
    @Published public var error: Error?

    private var currentURL: URL?

    public init() {}

    /// Fetch metadata for a URL.
    public func fetchMetadata(for url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        isLoading = true
        error = nil

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.error = error
                    self?.metadata = LinkPreviewData(url: url)
                } else if let metadata = metadata {
                    self?.metadata = LinkPreviewData(
                        url: url,
                        title: metadata.title,
                        description: nil,
                        imageUrl: nil,
                        siteName: metadata.url?.host
                    )
                } else {
                    self?.metadata = LinkPreviewData(url: url)
                }
            }
        }
    }

    /// Clear current metadata.
    public func clear() {
        currentURL = nil
        metadata = nil
        isLoading = false
        error = nil
    }
}
