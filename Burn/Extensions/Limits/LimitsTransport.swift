import Foundation

/// Injected so the clients can be tested without a network — tests hand back canned bodies.
typealias LimitsTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

enum LimitsHTTP {
    static let live: LimitsTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    /// Both usage APIs are undocumented, so anything but 200 gets classified rather than parsed.
    static func failure(for status: Int) -> LimitsFailure? {
        switch status {
        case 200..<300: return nil
        case 401, 403:  return LimitsFailure(kind: .unauthorized, detail: nil)
        case 429:       return LimitsFailure(kind: .rateLimited, detail: nil)
        default:        return LimitsFailure(kind: .network, detail: "HTTP \(status)")
        }
    }
}

/// `resets_at` comes back as an ISO-8601 string on Claude and unix seconds on Codex.
struct APITimestamp: Decodable, Hashable {
    let date: Date?

    init(date: Date?) {
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.date = nil
        } else if let seconds = try? container.decode(Double.self) {
            self.date = Date(timeIntervalSince1970: seconds)
        } else if let text = try? container.decode(String.self) {
            self.date = Self.parse(text)
        } else {
            self.date = nil
        }
    }

    static func parse(_ text: String) -> Date? {
        for formatter in [withFraction, plain] {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()
}
