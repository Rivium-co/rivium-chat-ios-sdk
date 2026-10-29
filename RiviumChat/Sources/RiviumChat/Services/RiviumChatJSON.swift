import Foundation

/// JSON decoding as the Chat API sends it.
enum RiviumChatJSON {

    /// A decoder for API and realtime payloads.
    ///
    /// Server dates carry milliseconds ("2026-10-29T10:00:00.123Z"). Before
    /// iOS 26 `.iso8601` refuses them, so dates are read with and without
    /// fractional seconds.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 date, got \"\(text)\""
                )
            }
            return date
        }
        return decoder
    }

    /// An ISO 8601 date with or without fractional seconds, or nil.
    static func parseDate(_ text: String) -> Date? {
        withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }

    // ISO8601DateFormatter is thread-safe, so one shared instance each.
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction = ISO8601DateFormatter()
}

/// Builds Chat API paths, `/api/v1/<segments>?<query>`.
///
/// Each segment and query value is percent-encoded with a strict set (ASCII
/// letters, digits and `-._~` only), so `/`, `?`, `#`, `&`, `=`, `+`, `%`,
/// spaces and non-ASCII text in caller-supplied IDs and search text arrive at
/// the server exactly as given. Query entries whose value is nil are left out.
enum ApiRoute {

    static func path(_ segments: [String], query: [(String, String?)] = []) throws -> String {
        var path = "/api/v1"
        for segment in segments {
            // "", "." and ".." would point the request at a different route.
            guard !segment.isEmpty, segment != ".", segment != ".." else {
                throw RiviumChatError.invalidURL
            }
            path += "/" + encode(segment)
        }
        let items = query.compactMap { name, value in value.map { encode(name) + "=" + encode($0) } }
        if !items.isEmpty {
            path += "?" + items.joined(separator: "&")
        }
        return path
    }

    private static let unreserved: CharacterSet = {
        // Not CharacterSet.alphanumerics: that one includes non-ASCII letters.
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
