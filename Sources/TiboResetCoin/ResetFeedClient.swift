import Foundation

struct ResetFeedSnapshot: Decodable, Sendable {
    let version: Int
    let source: String
    let checkedAt: String?
    let lastResetAt: String?
    let event: ResetFeedEvent?
}

struct ResetFeedEvent: Decodable, Sendable {
    let id: String
    let signal: String
    let text: String
    let url: String
    let createdAt: String
}

@MainActor
final class ResetFeedClient {
    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func fetchLatest() async throws -> ResetFeedSnapshot {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResetFeedError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ResetFeedError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ResetFeedSnapshot.self, from: data)
        } catch {
            throw ResetFeedError.invalidPayload
        }
    }

    static func date(from rawValue: String?) -> Date? {
        guard let rawValue else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: rawValue) {
            return date
        }
        return ISO8601DateFormatter().date(from: rawValue)
    }
}

enum ResetFeedError: LocalizedError {
    case invalidResponse
    case invalidPayload
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Unexpected server response"
        case .invalidPayload:
            return "Invalid server data"
        case .http(let code):
            return "Server error \(code)"
        }
    }
}
